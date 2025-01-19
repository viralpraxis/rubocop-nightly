# frozen_string_literal: true

module RuboCop
  module Nightly
    class CLI
      def initialize(arguments)
        @options = Parser.parse(arguments)
      end

      def run
        Executor
          .new(Source.build(options.source, **options.source_options), options.executor_options)
          .call
      end

      private

      attr_reader :options
    end
  end
end
