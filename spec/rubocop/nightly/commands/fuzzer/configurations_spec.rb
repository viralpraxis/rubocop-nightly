# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Commands::Fuzzer::Configurations do
  let(:data_home) { Dir.mktmpdir('rubocop-nightly-spec') }

  around do |example|
    with_environment_variable('XDG_DATA_HOME', data_home) do
      FileUtils.mkdir_p(RuboCop::Nightly::Runtime.gems_data_directory)
      example.run
    end
  ensure
    FileUtils.remove_entry(data_home)
  end

  describe '.build' do
    before { allow(RuboCop::Nightly::Configuration).to receive(:build) }

    it 'asks for a configuration with the plugins stripped out' do
      described_class.build(plugins: false)

      expect(RuboCop::Nightly::Configuration).to have_received(:build)
        .with(hash_including(remove_plugins: true, keep_core_departments: true))
    end

    it 'keeps them by default' do
      described_class.build

      expect(RuboCop::Nightly::Configuration).to have_received(:build)
        .with(hash_including(remove_plugins: false, keep_core_departments: false))
    end

    it 'leaves the target ruby version to the driven RuboCop by default' do
      described_class.build

      expect(RuboCop::Nightly::Configuration).to have_received(:build)
        .with(hash_including(target_ruby_version: nil, parser_engine: 'parser_prism'))
    end

    it 'leaves the parser engine to RuboCop when a version is named, so old grammars parse' do
      described_class.build(target_ruby_version: 2.7)

      expect(RuboCop::Nightly::Configuration).to have_received(:build)
        .with(hash_including(target_ruby_version: 2.7, parser_engine: 'default'))
    end
  end

  describe '.build without a gems directory' do
    it 'raises an actionable error' do
      FileUtils.remove_entry(RuboCop::Nightly::Runtime.gems_data_directory)

      expect { described_class.build }
        .to raise_error(RuboCop::Nightly::ConfigurationError, /rake gems:install/)
    end
  end

  describe '.target_ruby_versions' do
    before do
      allow(RuboCop::Nightly::Runtime).to receive(:supported_target_ruby_versions).and_return([2.7, 3.0, 3.4])
    end

    it 'makes a single pass when no version is requested' do
      expect(described_class.target_ruby_versions(nil)).to eq([nil])
    end

    it 'keeps the requested versions in the order they were given' do
      expect(described_class.target_ruby_versions([3.0, 2.7])).to eq([3.0, 2.7])
    end

    it 'expands `all` to every version the driven RuboCop supports' do
      expect(described_class.target_ruby_versions(:all)).to eq([2.7, 3.0, 3.4])
    end

    it 'rejects a version the driven RuboCop does not know rather than failing every batch' do
      expect { described_class.target_ruby_versions([3.0, 9.9]) }
        .to raise_error(RuboCop::Nightly::ConfigurationError, /9\.9.*expected one of 2\.7, 3\.0, 3\.4/)
    end

    context 'when the bundle cannot be probed' do
      before { allow(RuboCop::Nightly::Runtime).to receive(:supported_target_ruby_versions).and_return([]) }

      it 'has nothing to validate against and lets the requested versions through' do
        expect(described_class.target_ruby_versions([9.9])).to eq([9.9])
      end

      it 'falls back to a single pass for `all`' do
        expect(described_class.target_ruby_versions(:all)).to eq([nil])
      end
    end
  end
end
