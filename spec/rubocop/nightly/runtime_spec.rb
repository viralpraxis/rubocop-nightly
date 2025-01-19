# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Runtime do
  describe '.execute' do
    def parsed_configuration(data)
      YAML.load(data, permitted_classes: [Regexp, Symbol])
    end

    it 'performs commands and returns expected result', :aggregate_failures do
      stdout, stderr, exit = described_class.execute('--show-cops')

      expect(parsed_configuration(stdout).keys).to include('Bundler/DuplicatedGem')
      expect(parsed_configuration(stdout).keys).not_to include('ThreadSafety/DirChdir')
      expect(stderr).to be_empty
      expect(exit).to be_success
    end

    context 'with argument `require_plugins` set to `true`', :aggregate_failures do
      it 'performs command with required rubocop plugins and returns expected result' do
        stdout, stderr, exit = described_class.execute('--show-cops', require_plugins: true)

        expect(parsed_configuration(stdout).keys).to include('Bundler/DuplicatedGem')
        expect(parsed_configuration(stdout).keys).to include('ThreadSafety/DirChdir')
        expect(stderr).to be_empty
        expect(exit).to be_success
      end
    end
  end

  describe '.data_directory' do
    it 'has expected value' do
      expect(described_class.data_directory)
        .to be_a(Pathname).and be_frozen
        .and eq(Pathname(File.join(Dir.home, 'local', 'share', 'rubocop-nightly')))
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
