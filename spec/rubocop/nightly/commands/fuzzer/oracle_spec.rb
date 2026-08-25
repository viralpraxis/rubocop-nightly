# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Commands::Fuzzer::Oracle do
  subject(:oracle) do
    described_class.new(signature: signature, configuration_path: '/tmp/config.yml',
                        basename: 'thing_spec.rb', budget: budget, autocorrect: autocorrect)
  end

  let(:signature) do
    RuboCop::Nightly::Commands::Fuzzer::Signature.new(
      cop_name: 'Style/Thing', exception_class: 'NoMethodError', masked_message: 'boom'
    )
  end
  let(:budget) { RuboCop::Nightly::Commands::Fuzzer::Budget.new(seconds: 60, calls: 10) }
  let(:autocorrect) { false }

  def crash_line(path) = "An error occurred while Style/Thing cop was inspecting #{path}:1:1.\n"

  describe '#select_reproducing' do
    it 'returns nothing for an empty candidate list without spending budget', :aggregate_failures do
      allow(RuboCop::Nightly::Runtime).to receive(:execute)

      expect(oracle.select_reproducing([])).to eq([])
      expect(RuboCop::Nightly::Runtime).not_to have_received(:execute)
    end

    it 'returns nothing once the budget is exhausted' do
      exhausted = RuboCop::Nightly::Commands::Fuzzer::Budget.new(seconds: 60, calls: 0)
      spent = described_class.new(signature: signature, configuration_path: '/c.yml',
                                  basename: 'a.rb', budget: exhausted)

      expect(spent.select_reproducing(['x'])).to eq([])
    end

    it 'reports the indices of candidates that crashed' do
      allow(RuboCop::Nightly::Runtime).to receive(:execute) do |target, *|
        paths = Dir.glob(File.join(target, '*', 'thing_spec.rb'))
        ['', crash_line(paths.last), nil]
      end

      expect(oracle.select_reproducing(%w[a b])).to eq([1])
    end

    it 'ignores crashes reported for a different cop' do
      allow(RuboCop::Nightly::Runtime).to receive(:execute) do |target, *|
        path = Dir.glob(File.join(target, '*', 'thing_spec.rb')).first
        ['', "An error occurred while Style/Other cop was inspecting #{path}:1:1.\n", nil]
      end

      expect(oracle.select_reproducing(%w[a])).to eq([])
    end

    it 'treats a timeout as nothing reproducing' do
      allow(RuboCop::Nightly::Runtime).to receive(:execute).and_raise(RuboCop::Nightly::ExecutionTimeout)

      expect(oracle.select_reproducing(%w[a])).to eq([])
    end

    it 'preserves the basename so path-sensitive cops still fire' do
      seen = nil
      allow(RuboCop::Nightly::Runtime).to receive(:execute) do |target, *|
        seen = Dir.glob(File.join(target, '*', '*')).map { File.basename(it) }
        ['', '', nil]
      end

      oracle.select_reproducing(%w[a b])

      expect(seen).to all(eq('thing_spec.rb'))
    end
  end

  describe '#confirm' do
    it 'is true when the same crash signature comes back' do
      allow(RuboCop::Nightly::Runtime).to receive(:execute)
        .and_return(['', "Error: cause: #<NoMethodError: boom>\n", nil])

      expect(oracle.confirm('source')).to be(true)
    end

    it 'is false for a different exception class' do
      allow(RuboCop::Nightly::Runtime).to receive(:execute)
        .and_return(['', "Error: cause: #<IndexError: boom>\n", nil])

      expect(oracle.confirm('source')).to be(false)
    end

    it 'is false when nothing crashed' do
      allow(RuboCop::Nightly::Runtime).to receive(:execute).and_return(['', '', nil])

      expect(oracle.confirm('source')).to be(false)
    end

    it 'is granted even when the call budget is spent' do
      exhausted = RuboCop::Nightly::Commands::Fuzzer::Budget.new(seconds: 60, calls: 0)
      spent = described_class.new(signature: signature, configuration_path: '/c.yml',
                                  basename: 'a.rb', budget: exhausted)
      allow(RuboCop::Nightly::Runtime).to receive(:execute)
        .and_return(['', "Error: cause: #<NoMethodError: boom>\n", nil])

      expect(spent.confirm('source')).to be(true)
    end
  end

  describe 'autocorrect mode' do
    let(:autocorrect) { true }

    it 'passes --autocorrect through to RuboCop', :aggregate_failures do
      allow(RuboCop::Nightly::Runtime).to receive(:execute).and_return(['', '', nil])

      oracle.confirm('source')

      expect(RuboCop::Nightly::Runtime).to have_received(:execute) do |*args, **|
        expect(args).to include('--autocorrect', '--raise-cop-error')
      end
    end
  end
end
