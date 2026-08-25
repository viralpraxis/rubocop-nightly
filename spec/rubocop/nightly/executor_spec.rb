# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Executor do
  let(:source) { instance_double(RuboCop::Nightly::Source::Rubygems, fetch: paths) }
  let(:root) { Dir.mktmpdir('rubocop-nightly-executor') }
  # Real files with distinct content: the Executor deduplicates the corpus before batching.
  let(:paths) do
    %w[a b c].map { |name| File.join(root, "#{name}.rb").tap { |p| File.write(p, "# #{name}\n") } }
  end
  let(:runner) { instance_double(RuboCop::Nightly::Commands::Fuzzer::Runner, run: Set.new) }

  after { FileUtils.remove_entry(root) }

  before do
    allow(RuboCop::Nightly::Commands::Fuzzer::Runner)
      .to receive_messages(new: runner, build_configuration: :configuration)
  end

  # Executor sets the global log level from its options; keep the suite output quiet.
  def build(**options) = described_class.new(source, { log_level: 'FATAL' }.merge(options))

  describe '#call' do
    # The default `options = {}` used to raise KeyError on the first fetch.
    it 'works with no options at all' do
      expect { described_class.new(source).call }.not_to raise_error
    end

    it 'batches according to batch_size' do
      build(batch_size: 2).call

      expect(RuboCop::Nightly::Commands::Fuzzer::Runner).to have_received(:new).twice
    end

    # Building it costs a subprocess plus a full dependency-mining pass; it must not happen
    # once per batch.
    it 'builds the configuration once for the whole run' do
      build(batch_size: 1).call

      expect(RuboCop::Nightly::Commands::Fuzzer::Runner).to have_received(:build_configuration).once
    end

    it 'shares one error set across batches so a crash is reported once', :aggregate_failures do
      build(batch_size: 1).call

      sets = []
      expect(RuboCop::Nightly::Commands::Fuzzer::Runner).to have_received(:new).exactly(3).times do |_, **kwargs|
        sets << kwargs[:errors]
      end
      expect(sets.uniq(&:object_id).size).to eq(1)
    end

    # Source::Rubygems used to `return` nil when nothing was published.
    context 'when the source yields nil' do
      let(:paths) { nil }

      it 'does not raise NoMethodError on nil' do
        expect { build.call }.not_to raise_error
      end

      it 'reports success' do
        expect(build.call).to be_success
      end
    end

    context 'when a batch raises' do
      before { allow(runner).to receive(:run).and_raise(StandardError, 'boom') }

      it 'continues with the remaining batches' do
        build(batch_size: 1).call

        expect(RuboCop::Nightly::Commands::Fuzzer::Runner).to have_received(:new).exactly(3).times
      end

      it 'records the failure in the result' do
        expect(build(batch_size: 1).call.failed_batches).to eq(3)
      end

      it 'does not report success' do
        expect(build(batch_size: 1).call).not_to be_success
      end
    end

    context 'when a batch times out' do
      before { allow(runner).to receive(:run).and_raise(RuboCop::Nightly::ExecutionTimeout) }

      it 'records it and carries on' do
        expect(build(batch_size: 1, batch_timeout: 1).call.failed_batches).to eq(3)
      end
    end

    context 'with detected cop errors' do
      it 'does not report success' do
        allow(runner).to receive(:run).and_return(nil)
        executor = build(batch_size: 3)
        allow(RuboCop::Nightly::Commands::Fuzzer::Runner).to receive(:new) do |_, **kwargs|
          kwargs[:errors] << :boom
          runner
        end

        expect(executor.call).not_to be_success
      end
    end

    it 'rejects a non-positive batch size' do
      expect { build(batch_size: 0).call }
        .to raise_error(RuboCop::Nightly::ConfigurationError, /positive integer/)
    end

    it 'rejects an unknown log level' do
      expect { described_class.new(source, log_level: 'LOUD').call }
        .to raise_error(RuboCop::Nightly::ConfigurationError, /unknown log level/)
    end
  end
end
