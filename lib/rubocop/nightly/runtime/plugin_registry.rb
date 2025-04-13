# frozen_string_literal: true

require 'yaml'
require 'pathname'

module RuboCop
  module Nightly
    module Runtime
      class PluginRegistry
        CONFIGUTATION_FILEPATH = Pathname('config/gems.yml').freeze
        ALL = YAML.safe_load_file(CONFIGUTATION_FILEPATH).select { it['type'] == 'plugin' }.each(&:freeze).freeze
        ALL_NAMES = ALL.map { it.fetch('name').freeze }.freeze

        class << self
          def all = ALL
          def all_names = ALL_NAMES
        end
      end
    end
  end
end
