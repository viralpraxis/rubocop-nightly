# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Runtime do
  describe '.execute' do
    def parsed_configuration(data)
      YAML.load(data, permitted_classes: [Regexp, Symbol])
    end

    it 'performs commands and returns expected result', :aggregate_failures do
      stdout, stderr, status = described_class.execute(
        '--show-cops',
        '-c', fixture_path('configurations/basic.yml'),
        fixture_path(bundle_gemfile: fixture_path('gemfiles/Gemfile.pristine'))
      )

      expect(stderr).to be_empty
      expect(status).to be_success

      expect(parsed_configuration(stdout).keys).to include('Bundler/DuplicatedGem')
    end

    context 'with argument `require_plugins` set to `true`', :aggregate_failures do
      it 'performs command with required rubocop plugins and returns expected result', skip: :ci_fix do
        stdout, stderr, status = described_class.execute(
          '--show-cops',
          '-c', fixture_path('configurations/basic.yml'),
          require_plugins: true,
          bundle_gemfile: fixture_path('gemfiles/Gemfile.plugins')
        )

        expect(stderr.split("\n").reject { it.include?('gem supports plugin') }).to be_empty
        expect(status).to be_success

        expect(parsed_configuration(stdout).keys).to include('Bundler/DuplicatedGem')
        expect(parsed_configuration(stdout).keys).to include('ThreadSafety/DirChdir')
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
  end
end
