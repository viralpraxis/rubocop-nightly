# frozen_string_literal: true

require 'yaml'
require 'optparse'

module RuboCop
  module Nightly
    class CLI
      class Parser # rubocop:disable Metrics/ClassLength
        BATCH_SIZE_DEFAULT = 100
        private_constant(*constants(false))

        FuzzerOptions = Data.define(
          :source,
          :mirror_path,
          :git_sources,
          :batch_size,
          :batch_timeout,
          :log_level
        ) do
          def initialize( # rubocop:disable Metrics/ParameterLists
            source:,
            mirror_path: nil,
            git_sources: nil,
            batch_size: BATCH_SIZE_DEFAULT,
            batch_timeout: nil,
            log_level: 'INFO'
          )
            super
          end

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

          def command = :fuzzer
        end

        CompareOptions = Data.define(:from, :to, :source) do
          def command = :compare
        end

        class << self
          def parse(arguments) # rubocop:disable Metrics
            raw_options = {}
            command = ARGV.shift
            option_parser(raw_options, command).parse!(arguments)

            if command == 'fuzzer'
              validate_fuzzer_arguments!(raw_options)
              validate_mirror_specific_arguments!(raw_options)
              validate_git_specific_arguments!(raw_options)
            elsif command == 'compare'
              validate_comparer_arguments!(raw_options)
            else
              raise ArgumentError, command
            end

            options_class = fetch_options_class(command)
            options_class.new(**raw_options.slice(*options_class.members))
          end

          private

          def fetch_options_class(command)
            { 'fuzzer' => FuzzerOptions, 'compare' => CompareOptions }.fetch(command)
          end

          def option_parser(storage, command)
            OptionParser.new do |parser|
              parser.banner = 'Usage: rubocop-nightly command [options]'

              if command == 'fuzzer'
                apply_fuzzer_parser_options(parser, storage)
              elsif command == 'compare'
                apply_comparer_parser_options(parser, storage)
              end
            end
          end

          def apply_fuzzer_parser_options(parser, storage) # rubocop:disable Metrics
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

          def apply_comparer_parser_options(parser, storage)
            parser.on('-f FROM', '--from FROM', 'RuboCop revision') { storage[:from] = it }
            parser.on('-t TO', '--to TO', 'RuboCop revision') { storage[:to] = it }
            parser.on('-s SOURCE', '--source SOURCE', 'Git URL to apply comparsion to') { storage[:source] = it }
          end

          def validate_comparer_arguments!(arguments)
            raise OptionParser::MissingArgument, '--from' unless arguments[:from]
            raise OptionParser::MissingArgument, '--to' unless arguments[:to]
            raise OptionParser::MissingArgument, '--source' unless arguments[:source]
          end

          def validate_fuzzer_arguments!(arguments)
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
