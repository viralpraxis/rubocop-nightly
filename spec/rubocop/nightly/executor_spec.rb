# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Executor do
  let(:source) { instance_double(RuboCop::Nightly::Source::Rubygems, fetch: paths) }
  let(:root) { Dir.mktmpdir('rubocop-nightly-executor') }
  let(:paths) do
    %w[a b c].map { |name| File.join(root, "#{name}.rb").tap { |p| File.write(p, "# #{name}\n") } }
  end
  let(:runner) { instance_double(RuboCop::Nightly::Commands::Fuzzer::Runner, run: Set.new) }

  after { FileUtils.remove_entry(root) }

  before do
    allow(RuboCop::Nightly::Commands::Fuzzer::Runner).to receive(:new).and_return(runner)
    allow(RuboCop::Nightly::Commands::Fuzzer::Configurations).to receive(:build) do |target_ruby_version:, **|
      instance_double(RuboCop::Nightly::Configuration, target_ruby_version: target_ruby_version)
    end
  end

  def build(**options) = described_class.new(source, { log_level: 'FATAL' }.merge(options))

  describe '#call' do
    it 'does not reduce unless asked' do
      build(batch_size: 3).call

      expect(RuboCop::Nightly::Commands::Fuzzer::Runner).to have_received(:new).with(anything,
                                                                                     hash_including(reduce: false))
    end

    it 'works with no options at all' do
      expect { described_class.new(source).call }.not_to raise_error
    end

    it 'batches according to batch_size' do
      build(batch_size: 2).call

      expect(RuboCop::Nightly::Commands::Fuzzer::Runner).to have_received(:new).twice
    end

    it 'builds the configuration once for the whole run' do
      build(batch_size: 1).call

      expect(RuboCop::Nightly::Commands::Fuzzer::Configurations).to have_received(:build).once
    end

    it 'shares one error set across batches so a crash is reported once', :aggregate_failures do
      build(batch_size: 1).call

      sets = []
      expect(RuboCop::Nightly::Commands::Fuzzer::Runner).to have_received(:new).exactly(3).times do |_, **kwargs|
        sets << kwargs[:errors]
      end
      expect(sets.uniq(&:object_id).size).to eq(1)
    end

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
        expect(build(batch_size: 1, batch_timeout: 1).call.timed_out_batches).to eq(3)
      end

      it 'does not count it as a failed batch' do
        expect(build(batch_size: 1, batch_timeout: 1).call.failed_batches).to eq(0)
      end

      it 'does not report success' do
        expect(build(batch_size: 1, batch_timeout: 1).call).not_to be_success
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

    describe 'target ruby versions' do
      it 'makes one pass over the corpus per requested version' do
        build(batch_size: 3, target_ruby_versions: [2.7, 3.0]).call

        expect(RuboCop::Nightly::Commands::Fuzzer::Runner).to have_received(:new).twice
      end

      it 'runs each batch against each version' do
        build(batch_size: 1, target_ruby_versions: [2.7, 3.0]).call

        expect(RuboCop::Nightly::Commands::Fuzzer::Runner).to have_received(:new).exactly(6).times
      end

      it 'hands every pass the configuration built for it', :aggregate_failures do
        build(batch_size: 3, target_ruby_versions: [2.7, 3.0]).call

        versions = []
        expect(RuboCop::Nightly::Commands::Fuzzer::Runner).to have_received(:new).twice do |_, **kwargs|
          versions << kwargs[:configuration].target_ruby_version
        end
        expect(versions).to eq([2.7, 3.0])
      end

      it 'shares one findings set across the passes', :aggregate_failures do
        build(batch_size: 3, target_ruby_versions: [2.7, 3.0]).call

        sets = []
        expect(RuboCop::Nightly::Commands::Fuzzer::Runner).to have_received(:new).twice do |_, **kwargs|
          sets << kwargs[:findings]
        end
        expect(sets.uniq(&:object_id).size).to eq(1)
      end

      it 'builds one configuration per pass rather than all of them up front' do
        build(batch_size: 1, target_ruby_versions: [2.7, 3.0]).call

        expect(RuboCop::Nightly::Commands::Fuzzer::Configurations).to have_received(:build).twice
      end

      it 'resolves what the run was asked for' do
        allow(RuboCop::Nightly::Commands::Fuzzer::Configurations)
          .to receive(:target_ruby_versions).and_return([3.4])

        build(target_ruby_versions: :all).call

        expect(RuboCop::Nightly::Commands::Fuzzer::Configurations)
          .to have_received(:target_ruby_versions).with(:all)
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
