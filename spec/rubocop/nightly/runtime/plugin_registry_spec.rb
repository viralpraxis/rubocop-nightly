# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Runtime::PluginRegistry do
  describe '.all' do
    it 'is a frozen array' do
      expect(described_class.all).to be_an(Array).and be_frozen
    end

    it 'constains frozen hashes' do
      expect(described_class.all).to all(be_an(Hash).and(be_frozen))
    end
  end

  describe '.all_names' do
    it 'is a frozen array' do
      expect(described_class.all_names).to be_an(Array).and be_frozen
    end

    it 'contains frozen strings' do
      expect(described_class.all_names).to be_an(Array).and all(be_a(String).and(be_frozen))
    end
  end
end
