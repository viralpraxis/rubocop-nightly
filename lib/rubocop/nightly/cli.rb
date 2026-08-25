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
        return EXIT_SUCCESS if result.success?

        RuboCop::Nightly.logger.error(
          "Detected #{result.errors.size} cop error(s) across #{result.failed_batches} failed batch(es)"
        )
        EXIT_FAILURE
      end

      def run_compare(options)
        Commands::Compare.new(options).call ? EXIT_SUCCESS : EXIT_FAILURE
      end
    end
  end
end
