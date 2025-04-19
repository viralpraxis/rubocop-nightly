# frozen_string_literal: true

require 'tempfile'
require 'open3'

module RuboCop
  module Nightly
    module Commands
      module Fuzzer
        class Runner < Runner::Base
          ErrorDetails = Data.define(:cop_name, :source_pointer)

          CONFIGURATION_PATH = Pathname('/tmp/rubocop-nightly-configuration.yml').freeze
          ERROR_MESSAGE_REGEXP = /An error occurred while (?<cop_name>.+) cop was inspecting (?<source_pointer>.+)\z/
          private_constant :ERROR_MESSAGE_REGEXP

          def initialize(target_paths, configuration = Dir.chdir(Runtime.gems_data_directory) { Configuration.build })
            super()

            @target_paths = [*target_paths]
            @configuration = configuration
          end

          def run # rubocop:disable Metrics
            super

            @errors = Set.new

            configuration.variants.each_with_index do |(configuration_variant, cops), index|
              File.write(CONFIGURATION_PATH, configuration_variant.to_yaml)
              RuboCop::Nightly.logger.debug "Running iteration #{index}"

              _, stderr, status = Dir.chdir(Runtime.gems_data_directory) do
                Runtime.execute(
                  *target_paths,
                  '-c', CONFIGURATION_PATH.to_s,
                  '--format', 'RuboCop::Nightly::NullFormatter',
                  '--cache', 'false',
                  '-r', File.expand_path('../../null_formatter.rb', __dir__),
                  *(['--only', cops.join(',')] if cops),
                  require_plugins: true
                )
              end

              RuboCop::Nightly.logger.error(stderr_without_common_issues(stderr)) if status.exitstatus == 2

              rubocop_error_details = stderr.split("\n").grep(/An error occurred/).uniq.map { parse_error_message(it) }
              next if rubocop_error_details.empty?

              persisted_configuration_file = Tempfile.create
              persisted_configuration_file.write(File.read(CONFIGURATION_PATH))
              rubocop_error_details.each do |error_detail|
                next if @errors.include?(error_detail)

                @errors.add(error_detail)
                Nightly.logger.error(
                  "[#{persisted_configuration_file.path}] #{error_detail.cop_name}: #{error_detail.source_pointer}"
                )
              end
            end

            nil
          end

          private

          attr_reader :target_paths, :configuration

          def stderr_without_common_issues(stderr)
            stderr.split("\n").grep_v(/has the wrong namespace/).join("\n")
          end

          def parse_error_message(error_message)
            error_message.match(ERROR_MESSAGE_REGEXP).then do |match_data|
              ErrorDetails.new(cop_name: match_data[:cop_name], source_pointer: match_data[:source_pointer])
            end
          end
        end
      end
    end
  end
end
