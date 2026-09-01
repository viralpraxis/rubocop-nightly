# frozen_string_literal: true

module RuboCop
  module Nightly
    class CLI
      EXIT_SUCCESS = 0
      EXIT_FAILURE = 1
      EXIT_USAGE = 2

      def initialize(arguments)
        @arguments = arguments
      end

      def run
        dispatch(Parser.parse(arguments))
      rescue UsageError => e
        warn e.message
        EXIT_USAGE
      rescue RuboCop::Nightly::Error => e
        RuboCop::Nightly.logger.error "#{e.class}: #{e.message}"
        EXIT_FAILURE
      rescue Interrupt
        RuboCop::Nightly.logger.warn 'Interrupted'
        EXIT_FAILURE
      end

      private

      attr_reader :arguments

      def dispatch(options)
        case options.command
        when :help then print_and_succeed(options.text)
        when :version then print_and_succeed(RuboCop::Nightly::VERSION)
        when :fuzzer then run_fuzzer(options)
        when :compare then run_compare(options)
        end
      end

      def print_and_succeed(text)
        puts text
        EXIT_SUCCESS
      end

      def run_fuzzer(options)
        result = Executor
                 .new(Source.build(options.source, **options.source_options), options.executor_options)
                 .call

        report_fuzzer_result(result)
      end

      def report_fuzzer_result(result)
        report_warnings(result.findings.warnings)
        report_timed_out_batches(result.timed_out_batches)

        return EXIT_SUCCESS if result.success?

        RuboCop::Nightly.logger.error(
          "Detected #{result.findings} across #{result.failed_batches} failed " \
          "and #{result.timed_out_batches} timed-out batch(es)"
        )
        EXIT_FAILURE
      end

      # A Ruby warning is worth reading but is not a defect, so it never moves the exit status:
      # a noisy dependency must not be able to turn an otherwise clean night red. A batch that
      # ran out of time does fail the run, and is logged separately so the summary cannot be
      # mistaken for one blaming the warnings.
      def report_warnings(warnings)
        return if warnings.empty?

        RuboCop::Nightly.logger.info("Collected #{warnings.size} distinct Ruby warning(s)")
      end

      def report_timed_out_batches(count)
        return if count.zero?

        RuboCop::Nightly.logger.warn("#{count} batch(es) exceeded the batch timeout and were skipped")
      end

      def run_compare(options)
        Commands::Compare.new(options).call ? EXIT_SUCCESS : EXIT_FAILURE
      end
    end
  end
end
