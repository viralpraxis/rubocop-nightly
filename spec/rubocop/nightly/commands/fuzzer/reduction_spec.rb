# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Commands::Fuzzer::Reduction do
  subject(:reduction) { described_class.new(crash, variant) }

  let(:root) { Dir.mktmpdir('rubocop-nightly-reduction') }
  let(:target) { File.join(root, 'thing.rb') }
  let(:variant) { { 'AllCops' => {}, 'Style/Thing' => { 'Enabled' => true } } }
  let(:crash) do
    RuboCop::Nightly::Commands::Fuzzer::ErrorDetails.new(cop_name: 'Style/Thing', source_pointer: "#{target}:2:1")
  end

  before { File.write(target, "class Foo\n  BAR = 1\nend\n") }

  after { FileUtils.remove_entry(root) }

  describe '#call' do
    it 'returns nil when the crash carries no usable path' do
      pathless = RuboCop::Nightly::Commands::Fuzzer::ErrorDetails.new(
        cop_name: 'Style/Thing', source_pointer: '/nope/missing.rb'
      )

      expect(described_class.new(pathless, variant).call).to be_nil
    end

    it 'returns nil when the crash does not reproduce in isolation' do
      allow(RuboCop::Nightly::Runtime).to receive(:execute).and_return(['', '', nil])

      expect(reduction.call).to be_nil
    end

    it 'returns nil when the isolation run times out' do
      allow(RuboCop::Nightly::Runtime).to receive(:execute).and_raise(RuboCop::Nightly::ExecutionTimeout)

      expect(reduction.call).to be_nil
    end

    context 'when the crash reproduces' do
      let(:crash_output) { ['', "Error: cause: #<NoMethodError: boom>\n", nil] }

      before { allow(RuboCop::Nightly::Runtime).to receive(:execute).and_return(crash_output) }

      it 'returns a result carrying the crash signature' do
        expect(reduction.call.signature.exception_class).to eq('NoMethodError')
      end

      it 'reports the original size' do
        expect(reduction.call.original_size).to eq(3)
      end

      it 'keeps the original source when the reduced candidate cannot be confirmed' do
        allow_any_instance_of(RuboCop::Nightly::Commands::Fuzzer::Oracle) # rubocop:disable RSpec/AnyInstance
          .to receive(:confirm).and_return(false)

        expect(reduction.call.source).to eq(File.binread(target))
      end
    end
  end

  describe described_class::Result do
    let(:signature) do
      RuboCop::Nightly::Commands::Fuzzer::Signature.new(cop_name: 'A/B', exception_class: 'X', masked_message: 'm')
    end

    def result(source, original_size)
      described_class.new(signature: signature, source: source, configuration: { 'A/B' => {} },
                          basename: 'a.rb', original_size: original_size, budget: 'b')
    end

    it 'knows when it shrank the input' do
      expect(result("a\n", 5)).to be_reduced
    end

    it 'knows when it did not' do
      expect(result("a\nb\n", 2)).not_to be_reduced
    end
  end
end
