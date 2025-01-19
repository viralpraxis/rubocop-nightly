# frozen_string_literal: true

require 'yaml'

module RuboCop
  module Nightly
    class Configuration
      class << self
        def build(raw_configuration = load_configuration_from_rubocop_executable)
          apply_configuration_corrections(raw_configuration)

          new(raw_configuration)
        end

        private

        def load_configuration_from_rubocop_executable
          RuboCop::Nightly::Runtime
            .execute('--show-cops', require_plugins: true)
            .first
            .then { YAML.load(it, permitted_classes: [Regexp, Symbol]) }
        end

        def apply_configuration_corrections(raw_configuration) # rubocop:disable Metrics
          raw_configuration['require'] =
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
      end

      def dependencies
        @dependencies ||= DependenciesMiner.new(cop_names).mine
      end

      def cop_names
        @cop_names ||= raw_configuration.keys.select { %r{[A-Z][a-z]+/[A-Z][a-z]+}.match?(it) }
      end

      def variants
        @variants ||= basic_variants + dependent_variants
      end

      def variants_count = variants.size

      def basic_variants
        Array.new(@max_supported_styles_count) do |index|
          new_configuration = Marshal.load(Marshal.dump(@raw_configuration)) # dirty, should be lazy collection
          new_configuration.each_value do |value|
            next unless value.is_a?(Hash) && value.key?('SupportedStyles')

            supported_styles = value.fetch('SupportedStyles')

            value['EnforcedStyle'] = supported_styles[index.clamp(..supported_styles.size - 1)]
          end

          [new_configuration, nil]
        end
      end

      def dependent_variants # rubocop:disable Metrics
        variants = []

        dependencies.each do |primary_cop_name, possible_dependent_cop_names|
          next unless @raw_configuration.fetch(primary_cop_name).key?('SupportedStyles')

          primary_cop_supported_styles = @raw_configuration.fetch(primary_cop_name).fetch('SupportedStyles')
          dependent_cop_names = possible_dependent_cop_names.select do
            @raw_configuration[it].key?('SupportedStyles')
          end
          next if dependent_cop_names.empty?

          dependent_cop_supported_styles = dependent_cop_names.map { @raw_configuration[it].fetch('SupportedStyles') }

          all_cops = [primary_cop_supported_styles, *dependent_cop_supported_styles]
          all_cops.reduce(&:product).map(&:flatten).each do |conf|
            new_configuration = Marshal.load(Marshal.dump(@raw_configuration)) # dirty, should be lazy collection
            new_configuration[primary_cop_name]['EnforcedStyle'] = conf[0]
            conf[1..].each_with_index do |style, index|
              new_configuration[dependent_cop_names[index]]['EnforcedStyle'] = style
            end

            variants << [new_configuration, [primary_cop_name, *dependent_cop_names]]
          end
        end

        variants
      end

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
