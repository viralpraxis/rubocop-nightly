# frozen_string_literal: true

module RuboCop
  module Nightly
    class Configuration
      # rubocop:disable Metrics
      class Traversal
        def self.call(cops, dependencies)
          new(cops, dependencies).generate
        end

        def initialize(cops, dependencies)
          @cops = cops
          @dependencies = dependencies
          @visited = Set.new
        end

        attr_reader :visited

        def generate
          required = generate_all_required_combinations
          minimize_configs(required.to_a)
        end

        private

        def product_of(attributes)
          keys = attributes.keys
          values = attributes.values
          return [] if keys.empty?

          values[0].product(*values[1..]).map do |vals|
            keys.zip(vals).to_h
          end
        end

        def attribute_combinations(cop_name)
          relevant = [cop_name] + Array(@dependencies.fetch(cop_name, Set.new))
          attr_map = relevant.filter_map { |name| [name, @cops[name]] }.to_h

          all_attrs = attr_map.flat_map do |name, attrs|
            attrs&.map { |key, values| ["#{name}.#{key}", values] } || []
          end.to_h

          return [{ cop_name => {} }] if all_attrs.empty?

          combinations = product_of(all_attrs)

          combinations.map do |flat_attrs|
            nested = {}

            flat_attrs.each do |k, v|
              cop, attr = k.split('.', 2)
              nested[cop] ||= {}
              nested[cop][attr] = v
            end

            nested
          end
        end

        def generate_all_required_combinations
          required = Set.new

          # Add combinations for all cops
          @cops.each_key do |cop|
            attribute_combinations(cop).each { |combo| required.add(combo) }
          end

          # Remove cop from combinations where it has no variations
          required.map do |combo|
            combo.each_with_object({}) do |(cop, attrs), acc|
              if @cops[cop].empty? && !visited.include?(cop)
                acc[cop] ||= {}
              else
                acc[cop] = attrs
              end
            end
          end
        end

        def mergeable?(config1, config2)
          config1.all? do |cop, attrs|
            config2[cop].nil? || config2[cop].all? { |k, v| attrs[k].nil? || attrs[k] == v }
          end
        end

        def merge_configs(config1, config2)
          merged = Marshal.load(Marshal.dump(config1))
          config2.each do |cop, attrs|
            merged[cop] ||= {}
            merged[cop].merge!(attrs)
          end
          merged
        end

        def minimize_configs(all_combos)
          minimized = []

          all_combos.each do |combo|
            merged = false

            minimized.each_with_index do |existing, i|
              next unless mergeable?(existing, combo)

              minimized[i] = merge_configs(existing, combo)
              merged = true
              break
            end

            minimized << combo unless merged
          end

          minimized
        end
      end
      # rubocop:enable Metrics
    end
  end
end
