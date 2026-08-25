# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Runtime::PluginRegistry do
  let(:configured) { YAML.safe_load_file(described_class::CONFIGURATION_FILEPATH) || [] }

  describe '.all' do
    it 'is a frozen array' do
      expect(described_class.all).to be_an(Array).and be_frozen
    end

    it 'contains frozen hashes' do
      expect(described_class.all).to all(be_an(Hash).and(be_frozen))
    end

    it 'selects exactly the plugin entries from the configuration' do
      expect(described_class.all).to eq(configured.select { it['type'] == 'plugin' })
    end

    it 'excludes core entries' do
      expect(described_class.all.map { it['type'] }).to all(eq('plugin'))
    end
  end

  describe '.all_names' do
    it 'is a frozen array' do
      expect(described_class.all_names).to be_an(Array).and be_frozen
    end

    it 'contains frozen strings' do
      expect(described_class.all_names).to be_an(Array).and all(be_a(String).and(be_frozen))
    end

    it 'is the name of every plugin entry' do
      expect(described_class.all_names).to eq(described_class.all.map { it.fetch('name') })
    end
  end

  describe 'configuration lookup' do
    it 'is anchored to the gem rather than the working directory' do
      from_elsewhere = Dir.chdir(Dir.tmpdir) { described_class.all_names }

      expect(from_elsewhere).to eq(described_class.all_names)
    end

    it 'does not raise from an unrelated working directory' do
      expect { Dir.chdir(Dir.tmpdir) { described_class.all } }.not_to raise_error
    end
  end
end
