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

          # `findings` is supplied by the caller so that a defect seen in an earlier batch is not
          # reported again in every subsequent one.
          def initialize( # rubocop:disable Metrics/ParameterLists
            target_paths, configuration: nil, timeout: nil,
            findings: Findings.new, reduce: false, autocorrect: false
          )
            super()

            @target_paths = [*target_paths]
            @configuration = configuration || self.class.build_configuration
            @timeout = timeout
            @findings = findings
            @reduce = reduce
            @autocorrect = autocorrect
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

            findings
          end

          private

          attr_reader :target_paths, :configuration, :findings, :reduce, :autocorrect

          def run_variant(configuration_variant, index, configuration_path, deadline)
            File.write(configuration_path, configuration_variant.to_yaml)
            RuboCop::Nightly.logger.debug "Running iteration #{index}/#{configuration.variants_count}"

            Workspace.open(target_paths, autocorrect:) do |workspace|
              investigate(workspace, configuration_variant, index, configuration_path, deadline)
            end
          end

          def investigate(workspace, configuration_variant, index, configuration_path, deadline)
            stdout, stderr, status = invoke_rubocop(configuration_path, workspace.paths, remaining_time(deadline))
            outcome = Outcome.new(index:, configuration_path:, stdout:, stderr:, variant: configuration_variant)

            RuboCop::Nightly.logger.error(stderr_without_common_issues(stderr)) if status&.exitstatus == 2

            reporter.call(Diagnostics.parse(stderr, workspace:), workspace, outcome)
          end

          def reporter
            @reporter ||= Reporter.new(findings:, target_paths:, reduce:, autocorrect:)
          end

          def invoke_rubocop(configuration_path, paths, timeout)
            Dir.chdir(Runtime.gems_data_directory) do
              Runtime.execute(
                *rubocop_arguments(configuration_path, paths),
                require_plugins: true, timeout: timeout, warnings: true
              )
            end
          end

          # `--autocorrect-all` rather than `--autocorrect`: the unsafe corrections rewrite code
          # most aggressively, which is where the interesting bugs are. It stays compatible with
          # `--parallel`, which RuboCop only refuses alongside `--cache false`, `--fail-fast`,
          # `--profile` and `--memory`.
          def rubocop_arguments(configuration_path, paths)
            [
              '-c', configuration_path,
              '--format', 'RuboCop::Nightly::NullFormatter',
              '--parallel',
              *('--autocorrect-all' if autocorrect),
              '-r', File.expand_path('../../null_formatter.rb', __dir__),
              *paths
            ]
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
        end
      end
    end
  end
end
