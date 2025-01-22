# frozen_string_literal: true

require 'yaml'
require 'optparse'

module RuboCop
  module Nightly
    class CLI
      class Parser
        BATCH_SIZE_DEFAULT = 100
        private_constant(*constants(false))

        # rubocop:disable Metrics/ParameterLists
        Options = Data.define(:source, :mirror_path, :git_sources, :batch_size, :batch_timeout, :log_level) do
          def initialize(
            source:,
            mirror_path: nil,
            git_sources: nil,
            batch_size: BATCH_SIZE_DEFAULT,
            batch_timeout: nil,
            log_level: 'INFO'
          )
            super
          end
          # rubocop:enable Metrics/ParameterLists

          def source_options
            if source == 'mirror'
              { mirror_path: }
            elsif source == 'git'
              { sources: git_sources }
            else
              {}
            end
          end

          def executor_options
            { batch_size:, batch_timeout:, log_level: }
          end
        end

        class << self
          def parse(arguments)
            raw_options = {}
            option_parser(raw_options).parse!(arguments)

            validate_required_arguments!(raw_options)
            validate_mirror_specific_arguments!(raw_options)
            validate_git_specific_arguments!(raw_options)

            Options.new(**raw_options.slice(*Options.members))
          end

          private

          def option_parser(storage)
            OptionParser.new do |parser|
              parser.banner = 'Usage: example.rb [options]'

              apply_parser_options(parser, storage)
            end
          end

          def apply_parser_options(parser, storage) # rubocop:disable Metrics
            parser.on('-s SOURCE', '--source SOURCE', 'Source') { storage[:source] = it }
            parser.on('-b BATCH_SIZE', '--batch-size BATCH_SIZE', Integer, 'Batch size') { storage[:batch_size] = it }
            parser.on('-t', '--batch-timeout BATCH_TIMEOUT', Integer, 'Batch timeout (s)') do
              storage[:batch_timeout] = it
            end
            parser.on('-m MIRROR_PATH', '--mirror-path MIRROR_PATH', 'Mirror source data directory path') do
              storage[:mirror_path] = it
            end
            parser.on('-g GIT_SOURCES', '--git-sources', 'Git source to fetch') do
              storage[:git_sources] = YAML.safe_load_file(it)
            end
            parser.on('-l LOG_LEVEL', '--log-level LOG_LEVEL', 'Log level') { storage[:log_level] = it }
          end

          def validate_required_arguments!(arguments)
            return unless arguments[:source].nil? || arguments[:source].empty?

            raise OptionParser::MissingArgument, '--source'
          end

          def validate_mirror_specific_arguments!(arguments)
            return if arguments[:source] != 'mirror'
            return if arguments[:mirror_path] && !arguments[:mirror_path].empty?

            raise OptionParser::MissingArgument, '--mirror-path'
          end

          def validate_git_specific_arguments!(arguments)
            return if arguments[:source] != 'git'
            return if arguments[:git_sources] && !arguments[:git_sources].empty?

            raise OptionParser::MissingArgument, '--git-sources'
          end
        end
      end
    end
  end
end
