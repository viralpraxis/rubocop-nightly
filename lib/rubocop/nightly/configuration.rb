# frozen_string_literal: true

require 'yaml'

module RuboCop
  module Nightly
    class Configuration
      class << self
        def build(
          raw_configuration = nil,
          enable_all_cops: false,
          remove_plugins: false,
          keep_core_departments: false
        )
          raw_configuration ||= load_configuration_from_rubocop_executable(require_plugins: !remove_plugins)
          apply_configuration_corrections(raw_configuration)

          remove_plugins(raw_configuration) if remove_plugins
          enable_all_cops(raw_configuration) if enable_all_cops
          keep_core_departments(raw_configuration) if keep_core_departments
          remove_obsolete_attributes(raw_configuration)

          new(raw_configuration)
        end

        private

        def load_configuration_from_rubocop_executable(require_plugins: false)
          RuboCop::Nightly::Runtime
            .execute('--show-cops', require_plugins:)
            .fetch(0)
            .then { YAML.load(it, permitted_classes: [Regexp, Symbol]) }
        end

        def apply_configuration_corrections(raw_configuration) # rubocop:disable Metrics
          raw_configuration['plugins'] =
            RuboCop::Nightly::Runtime::PluginRegistry
            .all_names
          # .map { |plugin_name| RuboCop::Nightly::Runtime.plugin_require_path(plugin_name).to_s }

          if raw_configuration.key?('Style/Copyright')
            raw_configuration['Style/Copyright']['AutocorrectNotice'] =
              'Copyright 2025 Acme Inc'
          end

          if raw_configuration.key?('Style/ArgumentsForwarding')
            raw_configuration['Style/ArgumentsForwarding'].delete('AllowOnlyRestArgument')
          end

          raw_configuration.each_value do |cop_configuration|
            next unless cop_configuration.is_a?(Hash) && cop_configuration.key?('Enabled')

            cop_configuration['Enabled'] = true
          end
        end

        def enable_all_cops(raw_configuration)
          raw_configuration.transform_values do |value|
            value.tap { it['Enabled'] = true }
          end
        end

        def remove_plugins(raw_configuration)
          raw_configuration.delete('require')
          raw_configuration.delete('plugins')
        end

        def keep_core_departments(raw_configuration)
          raw_configuration.select! { |k, _| RuboCop::Nightly::Runtime::CORE_DEPARTMENTS.any? { k.start_with?(it) } }
        end

        def remove_obsolete_attributes(raw_configuration)
          raw_configuration.each_value { |value| value.delete('Include'); value.delete('Exclude') }
        end
      end

      def to_yaml
        YAML.dump(@raw_configuration)
      end

      def dependencies
        @dependencies ||= DependenciesMiner.new(cop_names).mine
      end

      def cop_names
        @cop_names ||= raw_configuration.keys.grep(%r{[A-Z][a-z]+/[A-Z][a-z]+})
      end

      def variants
        @variants ||= begin
          traversal_configuration = raw_configuration
                                    .select { |key, _| key.include?('/') }
                                    .transform_values do |cop_configuration|
            cop_configuration.slice('SupportedStyles')
          end
          result = Traversal.call(traversal_configuration, dependencies).map do |variant|
            new_configuration = Marshal.load(Marshal.dump(@raw_configuration))
            new_configuration.each do |key, value|
              next unless key.include?('/')

              value['Enabled'] = false unless key == 'Lint/Syntax'
            end
            variant.each do |cop_name, attributes|
              next if attributes.empty?

              new_configuration.fetch(cop_name)['EnforcedStyle'] = attributes.fetch('SupportedStyles')
              new_configuration.fetch(cop_name)['Enabled'] = true
            end
            new_configuration
          end
          result
        end
      end

      def variants_count = variants.size

      private

      attr_reader :raw_configuration

      def initialize(raw_configuration)
        @raw_configuration = raw_configuration
        @max_supported_styles_count = raw_configuration.map do |_, value|
          value.is_a?(Hash) ? value.fetch('SupportedStyles', []).size : 0
        end.max.clamp(1..)
      end
    end
  end
end
