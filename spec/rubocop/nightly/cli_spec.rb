# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::CLI do
  subject(:cli) { described_class.new(arguments) }

  let(:arguments) { [] }

  def run_silently(&) = expect(&).to output(anything).to_stdout

  describe '#run' do
    context 'with no arguments' do
      it 'prints usage and succeeds', :aggregate_failures do
        expect { expect(cli.run).to eq(described_class::EXIT_SUCCESS) }.to output(/Usage/).to_stdout
      end
    end

    context 'with --version' do
      let(:arguments) { %w[--version] }

      it 'prints the version and succeeds', :aggregate_failures do
        expect { expect(cli.run).to eq(described_class::EXIT_SUCCESS) }
          .to output(include(RuboCop::Nightly::VERSION)).to_stdout
      end
    end

    context 'with an unknown command' do
      let(:arguments) { %w[nope] }

      it 'reports usage on stderr and exits with the usage status', :aggregate_failures do
        expect { expect(cli.run).to eq(described_class::EXIT_USAGE) }.to output(/unknown command/).to_stderr
      end
    end

    context 'with the fuzzer command' do
      let(:arguments) { %w[fuzzer --source rubygems] }
      let(:result) { instance_double(RuboCop::Nightly::Executor::Result, success?: true, errors: [], failed_batches: 0) }

      before do
        allow(RuboCop::Nightly::Source).to receive(:build).and_return(instance_double(RuboCop::Nightly::Source::Rubygems))
        allow(RuboCop::Nightly::Executor).to receive(:new)
          .and_return(instance_double(RuboCop::Nightly::Executor, call: result))
      end

      it 'succeeds when no cop errors were detected' do
        expect(cli.run).to eq(described_class::EXIT_SUCCESS)
      end
    end

    context 'with the fuzzer command and detected cop errors' do
      let(:arguments) { %w[fuzzer --source rubygems] }
      let(:result) do
        instance_double(RuboCop::Nightly::Executor::Result, success?: false, errors: [:boom], failed_batches: 1)
      end

      before do
        allow(RuboCop::Nightly::Source).to receive(:build).and_return(instance_double(RuboCop::Nightly::Source::Rubygems))
        allow(RuboCop::Nightly::Executor).to receive(:new)
          .and_return(instance_double(RuboCop::Nightly::Executor, call: result))
        allow(RuboCop::Nightly.logger).to receive(:error)
      end

      it 'fails' do
        expect(cli.run).to eq(described_class::EXIT_FAILURE)
      end
    end

    context 'with the compare command' do
      let(:arguments) { %w[compare --from a --to b --source https://example.com/x.git] }
      let(:command) { instance_double(RuboCop::Nightly::Commands::Compare, call: unchanged) }
      let(:unchanged) { true }

      before { allow(RuboCop::Nightly::Commands::Compare).to receive(:new).and_return(command) }

      it 'succeeds when the revisions agree' do
        expect(cli.run).to eq(described_class::EXIT_SUCCESS)
      end
    end

    context 'with the compare command and differing revisions' do
      let(:arguments) { %w[compare --from a --to b --source https://example.com/x.git] }

      it 'fails' do
        allow(RuboCop::Nightly::Commands::Compare).to receive(:new)
          .and_return(instance_double(RuboCop::Nightly::Commands::Compare, call: false))

        expect(cli.run).to eq(described_class::EXIT_FAILURE)
      end
    end

    context 'when the run raises a nightly error' do
      let(:arguments) { %w[fuzzer --source rubygems] }

      it 'logs it and fails', :aggregate_failures do
        allow(RuboCop::Nightly.logger).to receive(:error)
        allow(RuboCop::Nightly::Source).to receive(:build).and_raise(RuboCop::Nightly::ConfigurationError, 'nope')

        expect(cli.run).to eq(described_class::EXIT_FAILURE)
        expect(RuboCop::Nightly.logger).to have_received(:error).with(/ConfigurationError: nope/)
      end
    end

    context 'when interrupted' do
      let(:arguments) { %w[fuzzer --source rubygems] }

      it 'reports the interruption and fails', :aggregate_failures do
        allow(RuboCop::Nightly.logger).to receive(:warn)
        allow(RuboCop::Nightly::Source).to receive(:build).and_raise(Interrupt)

        expect(cli.run).to eq(described_class::EXIT_FAILURE)
        expect(RuboCop::Nightly.logger).to have_received(:warn).with(/Interrupted/)
      end
    end
  end
end
