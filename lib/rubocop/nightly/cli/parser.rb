# frozen_string_literal: true

require 'yaml'
require 'optparse'

module RuboCop
  module Nightly
    class CLI
      class UsageError < RuboCop::Nightly::Error
      end

      class Parser # rubocop:disable Metrics/ClassLength
        BATCH_SIZE_DEFAULT = 1000
        LOG_LEVELS = %w[DEBUG INFO WARN ERROR FATAL UNKNOWN].freeze
        HELP_FLAGS = %w[help --help -h].freeze
        VERSION_FLAGS = %w[version --version -v].freeze
        BANNER = <<~BANNER
          Usage: rubocop-nightly <command> [options]

          Commands:
              fuzzer     Explore RuboCop's configuration state space against a corpus of Ruby code
              compare    Report offense differences between two RuboCop revisions

          Run `rubocop-nightly <command> --help` for command-specific options.
        BANNER

        private_constant(*constants(false))

        FuzzerOptions = Data.define(
          :source,
          :mirror_path,
          :git_sources,
          :batch_size,
          :batch_timeout,
          :log_level,
          :reduce,
          :autocorrect
        ) do
          def initialize( # rubocop:disable Metrics/ParameterLists
            source:,
            mirror_path: nil,
            git_sources: nil,
            batch_size: BATCH_SIZE_DEFAULT,
            batch_timeout: nil,
            log_level: 'INFO',
            reduce: false,
            autocorrect: false
          )
            super
          end

          def source_options
            case source
            when 'mirror' then { mirror_path: }
            when 'git' then { sources: git_sources }
            else {}
            end
          end

          def executor_options
            { batch_size:, batch_timeout:, log_level:, reduce:, autocorrect: }
          end

          def command = :fuzzer
        end

        CompareOptions = Data.define(:from, :to, :source) do
          def command = :compare
        end

        HelpOptions = Data.define(:text) do
          def command = :help
        end

        VersionOptions = Data.define do
          def command = :version
        end

        FUZZER_SWITCHES = [
          ['-s SOURCE', '--source SOURCE', 'Source', :source, nil],
          ['-b BATCH_SIZE', '--batch-size BATCH_SIZE', 'Files per batch', :batch_size, Integer],
          ['-t BATCH_TIMEOUT', '--batch-timeout BATCH_TIMEOUT', 'Batch timeout (s)', :batch_timeout, Integer],
          ['-m MIRROR_PATH', '--mirror-path MIRROR_PATH', 'Mirror data directory path', :mirror_path, nil],
          ['-g GIT_SOURCES', '--git-sources GIT_SOURCES', 'Path to a git sources YAML file',
           :git_sources_path, nil],
          ['-l LOG_LEVEL', '--log-level LOG_LEVEL', 'Log level', :log_level, nil],
          ['-R', '--[no-]reduce', 'Reduce each crash to a minimal reproducible example (off by default)',
           :reduce, nil],
          ['-A', '--[no-]autocorrect', 'Exercise the correction path too, against throwaway copies ' \
                                       'of the corpus (off by default)', :autocorrect, nil]
        ].freeze
        private_constant :FUZZER_SWITCHES

        class << self
          def parse(arguments)
            arguments = Array(arguments).dup
            command = arguments.shift

            return HelpOptions.new(text: BANNER) if command.nil? || HELP_FLAGS.include?(command)
            return VersionOptions.new if VERSION_FLAGS.include?(command)

            unless %w[fuzzer compare].include?(command)
              raise UsageError, "unknown command #{command.inspect}\n\n#{BANNER}"
            end

            parse_command(command, arguments)
          end

          private

          def parse_command(command, arguments)
            raw_options = {}
            parser = option_parser(raw_options, command)

            begin
              parser.parse!(arguments)
            rescue OptionParser::ParseError => e
              raise UsageError, "#{e.message}\n\n#{parser.help}"
            end

            return HelpOptions.new(text: parser.help) if raw_options[:help]

            validate!(command, raw_options, parser)
            build_options(command, raw_options)
          end

          def build_options(command, raw_options)
            options_class = { 'fuzzer' => FuzzerOptions, 'compare' => CompareOptions }.fetch(command)

            options_class.new(**raw_options.slice(*options_class.members))
          end

          def validate!(command, raw_options, parser)
            if command == 'fuzzer'
              validate_fuzzer_arguments!(raw_options)
              validate_mirror_specific_arguments!(raw_options)
              validate_git_specific_arguments!(raw_options)
            else
              validate_comparer_arguments!(raw_options)
            end
          rescue UsageError => e
            raise UsageError, "#{e.message}\n\n#{parser.help}"
          end

          def option_parser(storage, command)
            OptionParser.new do |parser|
              parser.banner = "Usage: rubocop-nightly #{command} [options]"

              if command == 'fuzzer'
                apply_fuzzer_parser_options(parser, storage)
              else
                apply_comparer_parser_options(parser, storage)
              end

              parser.on('-h', '--help', 'Print this message') { storage[:help] = true }
            end
          end

          def apply_fuzzer_parser_options(parser, storage)
            FUZZER_SWITCHES.each do |short, long, description, key, type|
              parser.on(short, long, *type, description) { |value| storage[key] = value }
            end
          end

          def apply_comparer_parser_options(parser, storage)
            parser.on('-f FROM', '--from FROM', 'RuboCop revision') { storage[:from] = it }
            parser.on('-t TO', '--to TO', 'RuboCop revision') { storage[:to] = it }
            parser.on('-s SOURCE', '--source SOURCE', 'Git URL to apply comparison to') { storage[:source] = it }
          end

          def validate_comparer_arguments!(arguments)
            %i[from to source].each do |name|
              value = arguments[name]
              raise UsageError, "missing argument: --#{name}" if value.nil? || value.empty?
            end
          end

          def validate_fuzzer_arguments!(arguments)
            source = arguments[:source]
            raise UsageError, 'missing argument: --source' if source.nil? || source.empty?

            unless Source.names.include?(source)
              raise UsageError, "unknown source #{source.inspect}, expected one of #{Source.names.join(', ')}"
            end

            validate_batch_size!(arguments)
            validate_batch_timeout!(arguments)
            validate_log_level!(arguments)
          end

          def validate_batch_size!(arguments)
            batch_size = arguments.fetch(:batch_size, BATCH_SIZE_DEFAULT)
            return if batch_size.positive?

            raise UsageError, "--batch-size must be a positive integer, got #{batch_size}"
          end

          def validate_batch_timeout!(arguments)
            batch_timeout = arguments[:batch_timeout]
            return if batch_timeout.nil? || batch_timeout.positive?

            raise UsageError, "--batch-timeout must be a positive integer, got #{batch_timeout}"
          end

          def validate_log_level!(arguments)
            log_level = arguments.fetch(:log_level, 'INFO')
            return if LOG_LEVELS.include?(log_level.to_s.upcase)

            raise UsageError, "unknown --log-level #{log_level.inspect}, expected one of #{LOG_LEVELS.join(', ')}"
          end

          def validate_mirror_specific_arguments!(arguments)
            return if arguments[:source] != 'mirror'
            return if arguments[:mirror_path] && !arguments[:mirror_path].empty?

            raise UsageError, 'missing argument: --mirror-path'
          end

          def validate_git_specific_arguments!(arguments)
            return if arguments[:source] != 'git'

            path = arguments[:git_sources_path]
            raise UsageError, 'missing argument: --git-sources' if path.nil? || path.empty?

            arguments[:git_sources] = load_git_sources(path)
          end

          def load_git_sources(path)
            sources = YAML.safe_load_file(path)

            unless sources.is_a?(Array) && !sources.empty? && sources.all? { it.is_a?(Hash) && it['url'] }
              raise UsageError, "#{path} must contain a non-empty list of mappings, each with a 'url' key"
            end

            sources
          rescue Errno::ENOENT
            raise UsageError, "--git-sources file not found: #{path}"
          rescue Psych::SyntaxError => e
            raise UsageError, "--git-sources file #{path} is not valid YAML: #{e.message}"
          end
        end
      end
    end
  end
end
