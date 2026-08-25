# frozen_string_literal: true

require 'yaml'

module RuboCop
  module Nightly
    class Configuration
      COP_NAME_PATTERN = %r{\A[A-Z]\w*(?:/[A-Z]\w*)+\z}

      class << self
        def build(...) = new(Builder.call(...))

        # Marshal round-trip is the cheapest deep copy for the plain Hash/Array/String trees
        # that make up a RuboCop configuration.
        def deep_copy(object) = Marshal.load(Marshal.dump(object))
      end

      def to_yaml
        YAML.dump(raw_configuration)
      end

      def dependencies
        @dependencies ||= DependenciesMiner.new(cop_names).mine
      end

      def cop_names
        @cop_names ||= raw_configuration.keys.grep(COP_NAME_PATTERN)
      end

      # Maps, per cop, each `Supported*` list to the `Enforced*` key it configures. The
      # pairing is derived by normalising both names — RuboCop's naming is not mechanically
      # derivable, `SupportedStylesAlignWith` pairs with `EnforcedStyleAlignWith` — and falls
      # back to the conventional name when the cop does not declare its partner explicitly.
      def style_parameters
        @style_parameters ||= cop_names.to_h { [it, style_parameters_for(it)] }
      end

      def variants
        @variants ||= begin
          template = Marshal.dump(raw_configuration)

          Traversal.call(traversal_configuration, dependencies).map do |variant|
            apply_variant(self.class.deep_copy_from(template), variant)
          end
        end
      end

      def variants_count = variants.size

      def self.deep_copy_from(dumped) = Marshal.load(dumped) # rubocop:disable Security/MarshalLoad

      private

      attr_reader :raw_configuration

      def initialize(raw_configuration)
        @raw_configuration = raw_configuration
      end

      # Not every `Supported*` key is a style axis: `Style/YodaExpression` has
      # `SupportedOperators` and `Layout/MultilineAssignmentLayout` has `SupportedTypes`,
      # neither of which names an `Enforced*` parameter. Writing an invented key there makes
      # RuboCop warn and ignore it, so only genuine pairs are kept.
      def style_parameters_for(cop_name)
        cop_configuration = raw_configuration[cop_name]
        return {} unless cop_configuration.is_a?(Hash)

        enforced = cop_configuration.keys.grep(/\AEnforced/).to_h { [normalize_style_key(it), it] }

        cop_configuration.keys.grep(/\ASupported/).filter_map do |key|
          partner = enforced[normalize_style_key(key)] || implicit_enforced_key(key)
          [key, partner] if partner
        end.to_h
      end

      def traversal_configuration
        cop_names.to_h do |cop_name|
          [cop_name, raw_configuration[cop_name].slice(*style_parameters.fetch(cop_name, {}).keys)]
        end
      end

      def apply_variant(configuration, variant)
        disable_cops(configuration)

        variant.each do |cop_name, attributes|
          cop_configuration = configuration[cop_name]
          next unless cop_configuration.is_a?(Hash)

          # A cop with no configurable styles still has to run — it just has a single variant.
          cop_configuration['Enabled'] = true
          apply_attributes(cop_configuration, cop_name, attributes)
        end

        configuration
      end

      def disable_cops(configuration)
        configuration.each do |key, value|
          next unless value.is_a?(Hash) && COP_NAME_PATTERN.match?(key) && key != 'Lint/Syntax'

          value['Enabled'] = false
        end
      end

      def apply_attributes(cop_configuration, cop_name, attributes)
        attributes.each do |supported_key, value|
          enforced_key = style_parameters.dig(cop_name, supported_key)
          cop_configuration[enforced_key] = value if enforced_key
        end
      end

      def normalize_style_key(key)
        key.delete_prefix('Supported').delete_prefix('Enforced').delete('s')
      end

      # `SupportedStyles`/`EnforcedStyle` is universal in RuboCop, so it is assumed even when
      # a configuration omits the `Enforced` half (hand-written configs often do). Every other
      # `Supported*` key must name its partner explicitly.
      def implicit_enforced_key(key)
        'EnforcedStyle' if key == 'SupportedStyles'
      end
    end
  end
end
