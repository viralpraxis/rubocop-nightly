# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Runtime::PluginRegistry do
  describe '.all' do
    it 'is a frozen array' do
      expect(described_class.all).to be_an(Array).and be_frozen
    end

    it 'contains frozen hashes' do
      expect(described_class.all).to all(be_an(Hash).and(be_frozen))
    end

    it 'is not empty' do
      expect(described_class.all).not_to be_empty
    end

    it 'only contains plugin entries' do
      expect(described_class.all.map { it['type'] }.uniq).to eq(['plugin'])
    end
  end

  describe '.all_names' do
    it 'is a frozen array' do
      expect(described_class.all_names).to be_an(Array).and be_frozen
    end

    it 'contains frozen strings' do
      expect(described_class.all_names).to be_an(Array).and all(be_a(String).and(be_frozen))
    end

    it 'is not empty' do
      expect(described_class.all_names).not_to be_empty
    end
  end

  # The configuration used to be read from a CWD-relative path at require time, so the
  # library could only be loaded from the repository root.
  describe 'configuration lookup' do
    it 'is anchored to the gem rather than the working directory' do
      Dir.chdir(Dir.tmpdir) do
        expect(described_class.all_names).not_to be_empty
      end
    end
  end
end
