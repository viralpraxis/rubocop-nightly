# frozen_string_literal: true

module RuboCop
  module Nightly
    class CLI
      def initialize(arguments)
        @options = Parser.parse(arguments)
      end

      def run
        if options.command == :fuzzer
          Executor # FIXME
            .new(Source.build(options.source, **options.source_options), options.executor_options)
            .call
        else
          Commands::Compare
            .new(options)
            .call
        end
      end

      private

      attr_reader :options
    end
  end
end
