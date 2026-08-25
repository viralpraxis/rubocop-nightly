# frozen_string_literal: true

RSpec.describe RuboCop::Nightly do
  it 'has a version number' do
    expect(RuboCop::Nightly::VERSION).not_to be_nil
  end

  describe '.logger' do
    it 'is memoized' do
      expect(described_class.logger).to equal(described_class.logger)
    end

    it 'writes to stderr so it cannot corrupt the compare command report on stdout' do
      expect(described_class.logger.instance_variable_get(:@logdev).dev).to be($stderr)
    end
  end
end
