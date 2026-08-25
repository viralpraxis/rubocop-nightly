# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Commands::Fuzzer::ErrorDetails do
  def details(pointer) = described_class.new(cop_name: 'Style/Thing', source_pointer: pointer)

  describe '#path' do
    it 'strips the line and column' do
      expect(details('/a/b.rb:12:3').path).to eq('/a/b.rb')
    end

    it 'returns the pointer unchanged when there is no location' do
      expect(details('/a/b.rb').path).to eq('/a/b.rb')
    end
  end

  describe '#line' do
    it 'extracts the line number' do
      expect(details('/a/b.rb:12:3').line).to eq(12)
    end

    it 'is nil for a path-only crash' do
      expect(details('/a/b.rb').line).to be_nil
    end
  end
end
