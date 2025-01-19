# frozen_string_literal: true

module RuboCop
  module Nightly
    class Executor
      def initialize(source, options = {})
        @source = source
        @options = options
      end

      def call # rubocop:disable Metrics
        base_paths = source.fetch
        total_batches_count = (base_paths.size.to_f / batch_size).ceil

        base_paths.each_slice(batch_size).with_index do |batch, index|
          RuboCop::Nightly.logger.debug "Processing group #{index.succ}/#{total_batches_count}"

          with_timeout do
            RuboCop::Nightly::Runner
              .new(prepare_target_paths(batch))
              .run
          rescue Timeout::Error
            RuboCop::Nightly.logger.debug "Processing group #{index.succ} took more than #{batch_timeout}s, aborting"
          end
        end
      end

      private

      def batch_size = @batch_size ||= options.fetch(:batch_size)

      def batch_timeout = @batch_timeout ||= options.fetch(:batch_timeout)

      def prepare_target_paths(paths)
        # paths.map { |path| path.end_with?('.rb') ? path : "#{path}/**/*.rb" } # FIXME
        paths
      end

      def with_timeout(&)
        if batch_timeout
          Timeout.timeout(batch_timeout, &)
        else
          yield
        end
      end

      attr_reader :source, :options
    end
  end
end
