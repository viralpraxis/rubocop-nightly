# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Runtime do
  describe '.execute' do
    def parsed_configuration(data)
      YAML.load(data, permitted_classes: [Regexp, Symbol])
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

    it 'passes the requested Gemfile through to the child environment', :aggregate_failures do
      allow(Open3).to receive(:popen3).and_raise(Errno::ENOENT, 'bundle')

      expect { described_class.execute('--version', bundle_gemfile: Pathname('/somewhere/Gemfile')) }
        .to raise_error(RuboCop::Nightly::ExecutableNotFound)

      expect(Open3).to have_received(:popen3)
        .with({ 'BUNDLE_GEMFILE' => '/somewhere/Gemfile' }, 'bundle', 'exec', 'rubocop', '--version', pgroup: true)
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
