# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Commands::Fuzzer::Budget do
  subject(:budget) { described_class.new(seconds: 30, calls: 2) }

  it 'grants claims until the call limit' do
    expect([budget.claim!, budget.claim!, budget.claim!]).to eq([true, true, false])
  end

  it 'reports exhaustion' do
    2.times { budget.claim! }

    expect(budget).to be_exhausted
  end

  it 'always grants a mandatory claim' do
    2.times { budget.claim! }

    expect(budget.claim!(mandatory: true)).to be(true)
  end

  it 'is exhausted once its time is up' do
    expect(described_class.new(seconds: 0, calls: 100)).to be_exhausted
  end

  it 'counts what it spent' do
    2.times { budget.claim! }

    expect(budget.spent).to eq(2)
  end
end
