# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Commands::Fuzzer::Reducer do
  let(:oracle) { fake_oracle(required) }
  let(:budget) { RuboCop::Nightly::Commands::Fuzzer::Budget.new(seconds: 30, calls: 200) }
  let(:required) { ['TRIGGER'] }

  def fake_oracle(fragments)
    calls = []
    oracle = Object.new
    oracle.define_singleton_method(:calls) { calls.size }
    oracle.define_singleton_method(:select_reproducing) do |sources|
      calls << sources.size
      sources.each_index.select { |index| fragments.all? { |f| sources[index].include?(f) } }
    end
    oracle
  end

  def reduce(source, pinned_line: nil)
    described_class.new(oracle:, budget:).call(source, pinned_line:)
  end

  it 'removes lines that are not needed' do
    source = "a\nb\nTRIGGER\nc\nd\n"

    expect(reduce(source)).to eq("TRIGGER\n")
  end

  context 'when several lines are required' do
    let(:required) { %w[OPEN TRIGGER CLOSE] }

    it 'keeps every one of them and drops the rest' do
      source = "OPEN\nnoise\nTRIGGER\nmore noise\nCLOSE\n"

      expect(reduce(source)).to eq("OPEN\nTRIGGER\nCLOSE\n")
    end
  end

  it 'never removes the pinned line even when the oracle would allow it' do
    source = "a\nb\nc\n"
    allow(oracle).to receive(:select_reproducing) { |sources| sources.each_index.to_a }

    expect(reduce(source, pinned_line: 2)).to eq("b\n")
  end

  it 'preserves the original line order' do
    expect(reduce("z\nTRIGGER\na\n")).to eq("TRIGGER\n")
  end

  it 'returns single-line sources untouched' do
    expect(reduce("TRIGGER\n")).to eq("TRIGGER\n")
  end

  it 'stops when nothing more can be removed' do
    reduce("a\nTRIGGER\nb\n")

    expect(oracle.calls).to be < 12
  end

  context 'with structurally coupled lines' do
    let(:required) { %w[OPEN TRIGGER CLOSE] }

    it 'still reduces the surrounding noise' do
      junk = (['junk'] * 8).join("\n")
      source = "#{junk}\nOPEN\nTRIGGER\nCLOSE\n#{junk}"

      expect(reduce(source)).to eq("OPEN\nTRIGGER\nCLOSE\n")
    end
  end

  context 'when the budget runs out' do
    let(:budget) { RuboCop::Nightly::Commands::Fuzzer::Budget.new(seconds: 30, calls: 1) }

    it 'returns the best result so far rather than failing' do
      expect(reduce("a\nTRIGGER\nb\n")).to include('TRIGGER')
    end
  end
end
