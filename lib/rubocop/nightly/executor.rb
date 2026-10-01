# frozen_string_literal: true

module RuboCop
  module Nightly
    class Executor
      # Batches are counted in files, not source entries. A whole 50-gem corpus in one batch
      # meant a single timeout lost every result; at 1000 files the RuboCop start-up cost
      # (~0.5s against ~0.05s per file) stays around 1% while the blast radius drops ~17x.
      DEFAULT_OPTIONS = {
        batch_size: 1000, batch_timeout: nil, log_level: 'INFO',
        reduce: false, autocorrect: false, plugins: true, only_show_types: nil,
        target_ruby_versions: nil
      }.freeze
      LOG_LEVELS = %w[DEBUG INFO WARN ERROR FATAL UNKNOWN].freeze

      # Timed-out batches are counted apart from failed ones so the report can say which of
      # the two happened, but both move the exit status: a batch that ran out of wall clock
      # left files uninspected, and that is coverage this night did not get to.
      Result = Data.define(:findings, :failed_batches, :timed_out_batches) do
        def initialize(findings:, failed_batches: 0, timed_out_batches: 0)
          super
        end

        def success? = findings.empty? && failed_batches.zero? && timed_out_batches.zero?

        def errors = findings.cop_errors
      end

      def initialize(source, options = {})
        @source = source
        @options = DEFAULT_OPTIONS.merge(options.compact)
        @findings = RuboCop::Nightly::Commands::Fuzzer::Findings.new
        @failed_batches = 0
        @timed_out_batches = 0
      end

      def call
        RuboCop::Nightly.logger.level = log_level

        passes = target_ruby_versions
        base_paths = Corpus.new(source.fetch).files
        passes.each { process_batches(base_paths, configuration_for(it)) } unless nothing_to_do?(base_paths)

        Result.new(
          findings: @findings, failed_batches: @failed_batches, timed_out_batches: @timed_out_batches
        )
      end

      private

      attr_reader :source, :options

      def process_batches(base_paths, configuration)
        total_batches_count = (base_paths.size.to_f / batch_size).ceil
        suffix = pass_suffix(configuration)

        base_paths.each_slice(batch_size).with_index do |batch, index|
          RuboCop::Nightly.logger.info "Processing group #{index.succ}/#{total_batches_count}#{suffix}"

          process(batch, index, configuration)
        end
      end

      def pass_suffix(configuration)
        options.fetch(:target_ruby_versions) ? " targeting Ruby #{configuration.target_ruby_version}" : ''
      end

      def nothing_to_do?(base_paths)
        return false unless base_paths.empty?

        RuboCop::Nightly.logger.info 'Nothing to analyze'
        true
      end

      # One bad batch must not take down a whole nightly run, but it must still be visible in
      # the exit status - whether it crashed or ran out of the time the batch timeout allows.
      def process(batch, index, configuration)
        RuboCop::Nightly::Commands::Fuzzer::Runner.new(batch, **runner_options(configuration)).run
      rescue ExecutionTimeout
        @timed_out_batches += 1
        RuboCop::Nightly.logger.warn(
          "Processing group #{index.succ}#{pass_suffix(configuration)} took more than #{batch_timeout}s, aborting"
        )
      rescue StandardError => e
        record_failure(index, configuration, e)
      end

      def runner_options(configuration)
        {
          configuration:, timeout: batch_timeout, findings: @findings,
          reduce: options.fetch(:reduce), autocorrect: options.fetch(:autocorrect),
          plugins: options.fetch(:plugins), only_show_types: options.fetch(:only_show_types)
        }
      end

      def record_failure(index, configuration, error)
        @failed_batches += 1
        RuboCop::Nightly.logger.error(
          "Processing group #{index.succ}#{pass_suffix(configuration)} failed: #{error.class}: #{error.message}"
        )
        RuboCop::Nightly.logger.debug error.backtrace&.join("\n")
      end

      # Built once per pass and shared by every batch of it: each one costs a
      # `rubocop --show-cops` subprocess, a dependency-mining pass over every cop source, and
      # the variant generation. Built when its pass starts rather than all of them up front,
      # so one set of variants is alive at a time however many versions were asked for.
      def configuration_for(target_ruby_version)
        RuboCop::Nightly::Commands::Fuzzer::Configurations.build(
          plugins: options.fetch(:plugins), target_ruby_version:
        )
      end

      def target_ruby_versions
        RuboCop::Nightly::Commands::Fuzzer::Configurations.target_ruby_versions(options.fetch(:target_ruby_versions))
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
