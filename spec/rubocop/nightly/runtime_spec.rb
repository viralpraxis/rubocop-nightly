# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Runtime do
  describe '.execute' do
    def parsed_configuration(data)
      YAML.load(data, permitted_classes: [Regexp, Symbol])
    end

    it 'still registers plugin cops when the default configuration is forced' do
      project_gemfile = Pathname(__dir__).join('../../../Gemfile').expand_path
      stdout, = described_class.execute(
        '--show-cops', '--force-default-config', '--plugin', 'rubocop-rspec', bundle_gemfile: project_gemfile
      )

      expect(parsed_configuration(stdout).keys).to include(a_string_starting_with('RSpec/'))
    end

    context 'when an ancestor directory holds a .rubocop.yml' do
      let(:root) { Pathname(Dir.mktmpdir('rubocop-nightly-ancestor')) }
      let(:working_directory) { root.join('work') }
      let(:project_gemfile) { Pathname(__dir__).join('../../../Gemfile').expand_path }

      before do
        working_directory.mkpath
        root.join('.rubocop.yml').write("plugins:\n  - rubocop-absent-from-this-bundle\n")
      end

      after { FileUtils.remove_entry(root) }

      def show_cops(*extra_arguments)
        Dir.chdir(working_directory) do
          described_class.execute('--show-cops', *extra_arguments, bundle_gemfile: project_gemfile)
        end
      end

      it 'aborts without the flag, because RuboCop merges configuration from above the CWD', :aggregate_failures do
        _stdout, stderr, status = show_cops

        expect(status).not_to be_success
        expect(stderr).to include('cannot load such file -- rubocop-absent-from-this-bundle')
      end

      it 'succeeds with --force-default-config' do
        _stdout, _stderr, status = show_cops('--force-default-config')

        expect(status).to be_success
      end

      it 'reports RuboCop own defaults rather than the ancestor configuration' do
        stdout, = show_cops('--force-default-config')

        expect(parsed_configuration(stdout).keys).to include('Style/Documentation')
      end
    end

    it 'performs commands and returns expected result', :aggregate_failures do
      stdout, stderr, status = described_class.execute(
        '--show-cops',
        '-c', fixture_path('configurations/basic.yml')
      )

      expect(stderr).to be_empty
      expect(status).to be_success

      expect(parsed_configuration(stdout).keys).to include('Bundler/DuplicatedGem')
    end

    describe 'the `warnings` argument' do
      def captured_environment(...)
        allow(Open3).to receive(:popen3).and_raise(Errno::ENOENT, 'bundle')

        expect { described_class.execute('--version', ...) }.to raise_error(RuboCop::Nightly::ExecutableNotFound)

        expect(Open3).to have_received(:popen3) { |environment, *| return environment }
      end

      # What the child inherits is whatever stood before Bundler activated, so these examples
      # pin that rather than assuming the suite itself was started without `RUBYOPT`.
      def with_pristine_rubyopt(&)
        with_environment_variable('RUBYOPT', nil) do
          with_environment_variable('BUNDLER_ORIG_RUBYOPT', 'BUNDLER_ENVIRONMENT_PRESERVER_INTENTIONALLY_NIL', &)
        end
      end

      # `nil` rather than absent: `unbundled_environment` is restoring the RUBYOPT that stood
      # before Bundler activated, and under Bundler that was nothing at all.
      it 'leaves RUBYOPT alone by default' do
        with_pristine_rubyopt do
          expect(captured_environment).to include('RUBYOPT' => nil)
        end
      end

      it 'asks the child for Ruby verbose mode when it is set' do
        with_pristine_rubyopt do
          expect(captured_environment(warnings: true)).to include('RUBYOPT' => '-W')
        end
      end

      it 'appends to the RUBYOPT the child would otherwise have been given' do
        with_environment_variable('BUNDLER_ORIG_RUBYOPT', '--yjit') do
          expect(captured_environment(warnings: true)).to include('RUBYOPT' => '--yjit -W')
        end
      end

      # The point of the flag: RuboCop's own load is warning-free, so a warning that reaches
      # stderr came out of the code under test.
      it 'actually reaches the RuboCop process' do
        _stdout, stderr, _status = described_class.execute(
          '--version', '-r', fixture_path('warning.rb'), warnings: true
        )

        expect(stderr).to include('warning: possibly useless use of == in void context')
      end

      it 'stays quiet without the flag' do
        stderr = with_pristine_rubyopt do
          described_class.execute('--version', '-r', fixture_path('warning.rb'))[1]
        end

        expect(stderr).not_to include('warning: possibly useless use')
      end
    end

    it 'passes the requested Gemfile through to the child environment', :aggregate_failures do
      allow(Open3).to receive(:popen3).and_raise(Errno::ENOENT, 'bundle')

      expect { described_class.execute('--version', bundle_gemfile: Pathname('/somewhere/Gemfile')) }
        .to raise_error(RuboCop::Nightly::ExecutableNotFound)

      expect(Open3).to have_received(:popen3).with(
        hash_including('BUNDLE_GEMFILE' => '/somewhere/Gemfile'),
        'bundle', 'exec', 'rubocop', '--version', pgroup: true
      )
    end

    context 'with argument `require_plugins` set to `true`', :aggregate_failures do
      let(:gemfile) { fixture_path('gemfiles/Gemfile.plugins') }

      before { skip_unless_bundle_installed(gemfile) }

      it 'performs command with required rubocop plugins and returns expected result' do
        stdout, stderr, status = described_class.execute(
          '--show-cops',
          '-c', fixture_path('configurations/basic.yml'),
          require_plugins: true,
          bundle_gemfile: Pathname(gemfile)
        )

        expect(stderr.split("\n").reject { it.include?('gem supports plugin') }).to be_empty
        expect(status).to be_success

        expect(parsed_configuration(stdout).keys).to include('Bundler/DuplicatedGem')
      end
    end

    context 'when the command exceeds its timeout' do
      it 'terminates the child and raises promptly', :aggregate_failures do
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        expect { described_class.send(:capture, {}, 'sleep', '30', timeout: 1) }
          .to raise_error(RuboCop::Nightly::ExecutionTimeout)

        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at).to be < 10
      end

      it 'kills the whole process group even when SIGTERM is ignored', :aggregate_failures do
        marker = File.join(Dir.tmpdir, "rubocop-nightly-spec-#{Process.pid}")
        script = "trap '' TERM; sleep 30 > #{marker} & wait"

        expect { described_class.send(:capture, {}, 'bash', '-c', script, timeout: 1) }
          .to raise_error(RuboCop::Nightly::ExecutionTimeout)

        sleep 0.2
        expect(`ps -eo args`.lines.count { it.include?(marker) }).to eq(0)
      end
    end

    context 'when running inside an activated Bundler environment' do
      around do |example|
        with_environment_variable('BUNDLE_LOCKFILE', '/parent/Gemfile.lock') do
          with_environment_variable('BUNDLER_ORIG_RUBYOPT', '-W0', &example)
        end
      end

      it 'clears the parent bundle out of the child environment', :aggregate_failures do
        allow(Open3).to receive(:popen3).and_raise(Errno::ENOENT, 'bundle')

        expect { described_class.execute('--version', bundle_gemfile: Pathname('/child/Gemfile')) }
          .to raise_error(RuboCop::Nightly::ExecutableNotFound)

        environment = nil
        expect(Open3).to have_received(:popen3) { |env, *| environment = env }

        expect(environment).to include('BUNDLE_LOCKFILE' => nil)
        expect(environment).to include('BUNDLE_GEMFILE' => '/child/Gemfile')
        expect(environment).to include('RUBYOPT' => '-W0')
      end

      it 'deletes rather than blanks the displaced variables', :aggregate_failures do
        allow(Open3).to receive(:popen3).and_raise(Errno::ENOENT, 'bundle')

        with_environment_variable('BUNDLER_ORIG_RUBYLIB', 'BUNDLER_ENVIRONMENT_PRESERVER_INTENTIONALLY_NIL') do
          expect { described_class.execute('--version') }.to raise_error(RuboCop::Nightly::ExecutableNotFound)
        end

        expect(Open3).to have_received(:popen3) { |env, *| expect(env['RUBYLIB']).to be_nil }
      end
    end

    context 'when the executable is missing' do
      it 'raises a descriptive error' do
        allow(Open3).to receive(:popen3).and_raise(Errno::ENOENT, 'bundle')

        expect { described_class.execute('--version') }
          .to raise_error(RuboCop::Nightly::ExecutableNotFound, /bundle exec rubocop/)
      end
    end
  end

  describe '.data_directory' do
    around { |example| with_environment_variable('XDG_DATA_HOME', nil, &example) }

    it 'has expected value' do
      expect(described_class.data_directory)
        .to be_a(Pathname).and be_frozen
        .and eq(Pathname(File.join(Dir.home, '.local', 'share', 'rubocop-nightly')))
    end

    context 'with set `XDG_DATA_HOME` environment variable' do
      around { |example| with_environment_variable('XDG_DATA_HOME', '/etc', &example) }

      it 'has expected value' do
        expect(described_class.data_directory)
          .to be_a(Pathname).and be_frozen
          .and eq(Pathname(File.join('/etc', 'rubocop-nightly')))
      end
    end

    context 'with an empty `XDG_DATA_HOME` environment variable' do
      around { |example| with_environment_variable('XDG_DATA_HOME', '', &example) }

      it 'falls back to the home directory instead of yielding a relative path' do
        expect(described_class.data_directory)
          .to eq(Pathname(File.join(Dir.home, '.local', 'share', 'rubocop-nightly')))
      end
    end
  end

  describe 'CORE_DEPARTMENTS' do
    it 'spells every department correctly', :aggregate_failures do
      expect(described_class::CORE_DEPARTMENTS).to include('Layout', 'Gemspec', 'Migration')
      expect(described_class::CORE_DEPARTMENTS).not_to include('Layour')
    end
  end
end
