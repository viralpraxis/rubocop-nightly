# frozen_string_literal: true

require 'yaml'

module RuboCop
  module Nightly
    module Runtime
      module PluginRegistry
        # Anchored to this file rather than the process CWD: the library is required from
        # `bin/`, from specs, and from inside `Dir.chdir` blocks that point elsewhere.
        CONFIGURATION_FILEPATH = Pathname(__dir__).join('../../../../config/gems.yml').expand_path.freeze

        class << self
          def all
            # rubocop:disable ThreadSafety/ClassInstanceVariable
            @all ||= load_configuration.select { it['type'] == 'plugin' }.each(&:freeze).freeze
          end

          def all_names = @all_names ||= all.map { it.fetch('name').freeze }.freeze
          # rubocop:enable ThreadSafety/ClassInstanceVariable

          private

          def load_configuration
            unless CONFIGURATION_FILEPATH.exist?
              raise ConfigurationError, "Gems configuration file not found at #{CONFIGURATION_FILEPATH}"
            end

            YAML.safe_load_file(CONFIGURATION_FILEPATH) || []
          end
        end
      end
    end
  end
end
