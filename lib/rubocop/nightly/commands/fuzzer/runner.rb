# frozen_string_literal: true

require 'tempfile'
require 'tmpdir'
require 'open3'

module RuboCop
  module Nightly
    module Commands
      module Fuzzer
        class Runner < Runner::Base
          ErrorDetails = Fuzzer::ErrorDetails

          Outcome = Data.define(:index, :configuration_path, :stdout, :stderr, :variant)

          ERROR_MESSAGE_REGEXP = /
            An\ error\ occurred\ while\ (?<cop_name>.+)\ cop\ was\ inspecting\ (?<source_pointer>.+?)\.?\z
          /x

          private_constant :ERROR_MESSAGE_REGEXP

          class << self
            def build_configuration
              Dir.chdir(Runtime.gems_data_directory) do
                Configuration.build(parser_engine: 'parser_prism')
              end
            rescue Errno::ENOENT
              raise ConfigurationError,
                    "RuboCop gems directory #{Runtime.gems_data_directory} does not exist — " \
                    'run `bundle exec rake gems:install` first'
            end
          end

          # `errors` is supplied by the caller so that a cop crash seen in an earlier batch is
          # not reported again in every subsequent one.
          def initialize(target_paths, configuration: nil, timeout: nil, errors: Set.new, reduce: false)
            super()

            @target_paths = [*target_paths]
            @configuration = configuration || self.class.build_configuration
            @timeout = timeout
            @errors = errors
            @reduce = reduce
          end

          def run
            super

            Dir.mktmpdir('rubocop-nightly') do |working_directory|
              configuration_path = File.join(working_directory, 'configuration.yml')
              deadline = @timeout && (monotonic_now + @timeout)

              configuration.variants.each_with_index do |configuration_variant, index|
                run_variant(configuration_variant, index, configuration_path, deadline)
              end
            end

            errors
          end

          private

          attr_reader :target_paths, :configuration, :errors, :reduce

          def run_variant(configuration_variant, index, configuration_path, deadline)
            File.write(configuration_path, configuration_variant.to_yaml)
            RuboCop::Nightly.logger.debug "Running iteration #{index}"

            stdout, stderr, status = invoke_rubocop(configuration_path, remaining_time(deadline))
            outcome = Outcome.new(index:, configuration_path:, stdout:, stderr:, variant: configuration_variant)

            RuboCop::Nightly.logger.error(stderr_without_common_issues(stderr)) if status.exitstatus == 2

            report_errors(parse_error_details(stderr), outcome)
          end

          def invoke_rubocop(configuration_path, timeout)
            Dir.chdir(Runtime.gems_data_directory) do
              Runtime.execute(*rubocop_arguments(configuration_path), require_plugins: true, timeout: timeout)
            end
          end

          def rubocop_arguments(configuration_path)
            [
              '-c', configuration_path,
              '--format', 'RuboCop::Nightly::NullFormatter',
              '--parallel',
              '-r', File.expand_path('../../null_formatter.rb', __dir__),
              *target_paths
            ]
          end

          def report_errors(error_details, outcome)
            unreported = error_details.reject { errors.include?(it) }
            return if unreported.empty?

            reproduction_path = Reproduction.persist(outcome, target_paths)

            unreported.each do |error_detail|
              errors.add(error_detail)
              RuboCop::Nightly.logger.error(
                "[#{reproduction_path}] #{error_detail.cop_name}: #{error_detail.source_pointer}"
              )
              # Every crash gets an MRE. `--reduce` only decides whether it is minimised first;
              # without it the example simply runs RuboCop against the whole offending file.
              Reproduction.write_mre(error_detail, outcome.variant, reproduction_path, reduce:)
            end
          end

          def parse_error_details(stderr)
            stderr.split("\n").grep(/An error occurred/).uniq.filter_map { parse_error_message(it) }
          end

          def remaining_time(deadline)
            return nil unless deadline

            remaining = deadline - monotonic_now
            raise ExecutionTimeout, 'batch deadline exceeded' unless remaining.positive?

            remaining
          end

          def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          def stderr_without_common_issues(stderr)
            stderr.split("\n").grep_v(/has the wrong namespace/).join("\n")
          end

          def parse_error_message(error_message)
            match_data = error_message.strip.match(ERROR_MESSAGE_REGEXP)

            unless match_data
              RuboCop::Nightly.logger.debug("Unrecognised RuboCop error line: #{error_message}")
              return nil
            end

            ErrorDetails.new(cop_name: match_data[:cop_name], source_pointer: match_data[:source_pointer])
          end
        end
      end
    end
  end
end
