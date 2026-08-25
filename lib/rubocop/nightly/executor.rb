# frozen_string_literal: true

module RuboCop
  module Nightly
    class Executor
      # Batches are counted in files, not source entries. A whole 50-gem corpus in one batch
      # meant a single timeout lost every result; at 1000 files the RuboCop start-up cost
      # (~0.5s against ~0.05s per file) stays around 1% while the blast radius drops ~17x.
      DEFAULT_OPTIONS = { batch_size: 1000, batch_timeout: nil, log_level: 'INFO', reduce: false }.freeze
      LOG_LEVELS = %w[DEBUG INFO WARN ERROR FATAL UNKNOWN].freeze

      Result = Data.define(:errors, :failed_batches) do
        def success? = errors.empty? && failed_batches.zero?
      end

      def initialize(source, options = {})
        @source = source
        @options = DEFAULT_OPTIONS.merge(options.compact)
        @errors = Set.new
        @failed_batches = 0
      end

      def call
        RuboCop::Nightly.logger.level = log_level

        base_paths = Corpus.new(source.fetch).files
        process_batches(base_paths) unless nothing_to_do?(base_paths)

        Result.new(errors: @errors, failed_batches: @failed_batches)
      end

      private

      attr_reader :source, :options

      def process_batches(base_paths)
        total_batches_count = (base_paths.size.to_f / batch_size).ceil

        base_paths.each_slice(batch_size).with_index do |batch, index|
          RuboCop::Nightly.logger.info "Processing group #{index.succ}/#{total_batches_count}"

          process(batch, index)
        end
      end

      def nothing_to_do?(base_paths)
        return false unless base_paths.empty?

        RuboCop::Nightly.logger.info 'Nothing to analyze'
        true
      end

      # One bad batch must not take down a whole nightly run, but it must still be visible
      # in the exit status.
      def process(batch, index)
        RuboCop::Nightly::Commands::Fuzzer::Runner
          .new(batch, configuration:, timeout: batch_timeout, errors: @errors, reduce: options.fetch(:reduce))
          .run
      rescue ExecutionTimeout
        @failed_batches += 1
        RuboCop::Nightly.logger.warn "Processing group #{index.succ} took more than #{batch_timeout}s, aborting"
      rescue StandardError => e
        record_failure(index, e)
      end

      def record_failure(index, error)
        @failed_batches += 1
        RuboCop::Nightly.logger.error "Processing group #{index.succ} failed: #{error.class}: #{error.message}"
        RuboCop::Nightly.logger.debug error.backtrace&.join("\n")
      end

      # Built once and shared by every batch: it costs a `rubocop --show-cops` subprocess,
      # a dependency-mining pass over every cop source, and the variant generation.
      def configuration
        @configuration ||= RuboCop::Nightly::Commands::Fuzzer::Runner.build_configuration
      end

      def batch_size
        @batch_size ||= options.fetch(:batch_size).then do |value|
          unless value.is_a?(Integer) && value.positive?
            raise ConfigurationError, "batch size must be a positive integer, got #{value.inspect}"
          end

          value
        end
      end

      def batch_timeout
        return @batch_timeout if defined?(@batch_timeout)

        @batch_timeout = options.fetch(:batch_timeout)
      end

      def log_level
        @log_level ||= options.fetch(:log_level).to_s.upcase.then do |value|
          unless LOG_LEVELS.include?(value)
            raise ConfigurationError, "unknown log level #{value.inspect}, expected one of #{LOG_LEVELS.join(', ')}"
          end

          value
        end
      end
    end
  end
end
