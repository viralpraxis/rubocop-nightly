# frozen_string_literal: true

require 'yaml'

module RuboCop
  module Nightly
    class Configuration
      # Turns a raw `rubocop --show-cops` dump (or a hand-written hash) into the configuration
      # the commands actually run with.
      class Builder
        def self.call(...) = new(...).call

        def initialize(
          raw_configuration = nil,
          enable_all_cops: false,
          remove_plugins: false,
          keep_core_departments: false,
          parser_engine: nil
        )
          @raw_configuration = raw_configuration
          @enable_all_cops = enable_all_cops
          @remove_plugins = remove_plugins
          @keep_core_departments = keep_core_departments
          @parser_engine = parser_engine
        end

        def call
          configuration = load_raw_configuration

          apply_corrections(configuration)
          remove_plugins(configuration) if @remove_plugins
          enable_all_cops(configuration) if @enable_all_cops
          keep_core_departments(configuration) if @keep_core_departments
          remove_obsolete_attributes(configuration)

          configuration
        end

        private

        def load_raw_configuration
          return Configuration.deep_copy(@raw_configuration) if @raw_configuration

          load_configuration_from_rubocop_executable(require_plugins: !@remove_plugins)
        end

        def load_configuration_from_rubocop_executable(require_plugins: false)
          stdout, stderr, status = RuboCop::Nightly::Runtime.execute('--show-cops', require_plugins:)

          unless status.success?
            raise ExecutionError, "`rubocop --show-cops` failed with status #{status.exitstatus}: #{stderr.strip}"
          end

          YAML.load(stdout, permitted_classes: [Regexp, Symbol]) ||
            raise(ExecutionError, '`rubocop --show-cops` produced no parseable configuration')
        end

        def apply_corrections(configuration)
          configuration['plugins'] = RuboCop::Nightly::Runtime::PluginRegistry.all_names.dup unless @remove_plugins
          configuration['AllCops'] = all_cops_section(configuration)

          configuration['Style/Copyright']&.[]=('AutocorrectNotice', 'Copyright 2025 Acme Inc')
          configuration['Style/ArgumentsForwarding']&.delete('AllowOnlyRestArgument')

          each_cop_configuration(configuration) do |cop_configuration|
            cop_configuration['Enabled'] = true if cop_configuration.key?('Enabled')
          end
        end

        # `rubocop --show-cops` emits cop entries only — never an `AllCops` section — so
        # without this RuboCop falls back to TargetRuby::DEFAULT_VERSION (2.7) and every
        # modern file is reported as a syntax error instead of being inspected.
        def all_cops_section(configuration)
          existing = configuration['AllCops']
          existing = {} unless existing.is_a?(Hash)

          existing.merge(
            'TargetRubyVersion' => RuboCop::Nightly::Runtime.target_ruby_version,
            'NewCops' => 'enable',
            'SuggestExtensions' => false
          ).tap { it['ParserEngine'] = @parser_engine if @parser_engine }
        end

        def enable_all_cops(configuration)
          each_cop_configuration(configuration) { it['Enabled'] = true }
        end

        def remove_plugins(configuration)
          configuration.delete('require')
          configuration.delete('plugins')
        end

        # Matches on the department segment rather than a bare `start_with?` so that `Style`
        # does not also swallow a hypothetical `StyleGuide` key.
        def keep_core_departments(configuration)
          configuration.select! do |key, _|
            key == 'AllCops' || RuboCop::Nightly::Runtime::CORE_DEPARTMENTS.include?(key.split('/', 2).first)
          end
        end

        def remove_obsolete_attributes(configuration)
          each_cop_configuration(configuration) do |cop_configuration|
            cop_configuration.delete('Include')
            cop_configuration.delete('Exclude')
          end
        end

        # `--show-cops` output is not uniformly a Hash-of-Hashes: `plugins` is an Array and
        # `require` may be a String, both of which blow up on `[]=`/`delete`.
        def each_cop_configuration(configuration)
          configuration.each do |key, value|
            next if key == 'AllCops'

            yield value if value.is_a?(Hash)
          end
        end
      end
    end
  end
end
