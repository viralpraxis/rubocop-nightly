# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Commands::Fuzzer::Signature do
  def parse(output, cop_name: 'Style/Thing') = described_class.parse(output, cop_name:)

  let(:crash) { 'Error: cause: #<IndexError: The range 14...15 is outside the bounds of the source>' }

  describe '.parse' do
    it 'extracts the exception class' do
      expect(parse(crash).exception_class).to eq('IndexError')
    end

    it 'is nil when the run did not crash' do
      expect(parse('nothing here')).to be_nil
    end
  end

  describe '#matches?' do
    it 'ignores source offsets embedded in the message' do
      shifted = 'Error: cause: #<IndexError: The range 37...38 is outside the bounds of the source>'

      expect(parse(crash)).to be_matches(parse(shifted))
    end

    it 'rejects a different exception class' do
      other = 'Error: cause: #<NoMethodError: undefined method>'

      expect(parse(crash)).not_to be_matches(parse(other))
    end

    it 'rejects a different cop' do
      expect(parse(crash)).not_to be_matches(parse(crash, cop_name: 'Style/Other'))
    end

    it 'rejects a different message from the same class' do
      other = 'Error: cause: #<IndexError: something else entirely>'

      expect(parse(crash)).not_to be_matches(parse(other))
    end

    it 'does not match a clean run' do
      expect(parse(crash)).not_to be_matches(parse('no cause line'))
    end
  end
end
