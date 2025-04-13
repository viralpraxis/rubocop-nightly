# frozen_string_literal: true

require 'tempfile'
require 'open3'

module RuboCop
  module Nightly
    class Runner
      CONFIGURATION_PATH = Pathname('/tmp/rubocop-nightly-configuration.yml').freeze

      def initialize(target_paths, configuration = Configuration.build)
        @target_paths = [*target_paths]
        @configuration = configuration
      end

      def run # rubocop:disable Metrics
        configuration.variants.each_with_index do |(configuration_variant, cops), index|
          File.write(CONFIGURATION_PATH, configuration_variant.to_yaml)
          RuboCop::Nightly.logger.debug "Running iteration #{index}"

          _, stderr, exit = Runtime.execute(
            *target_paths,
            '-c', CONFIGURATION_PATH.to_s,
            '--format', 'RuboCop::Nightly::NullFormatter',
            '--cache', 'false',
            '-r', "#{__dir__}/null_formatter.rb",
            *(['--only', cops.join(',')] if cops)
          )

          internal_errors = stderr.split("\n").grep(/\AError:/)
          internal_errors.each { RuboCop::Nightly.logger.error(it) }

          RuboCop::Nightly.logger.error(stderr) if exit.exitstatus == 2

          rubocop_errors = stderr.split("\n").grep(/An error occurred/).uniq
          next if rubocop_errors.empty?

          persisted_configuration_file = Tempfile.create
          persisted_configuration_file.write(File.read(CONFIGURATION_PATH))
          RuboCop::Nightly.logger.error "Using configuration #{persisted_configuration_file.path}"
          rubocop_errors.each { RuboCop::Nightly.logger.warn it }
        end

        nil
      end

      private

      attr_reader :target_paths, :configuration
    end
  end
end
