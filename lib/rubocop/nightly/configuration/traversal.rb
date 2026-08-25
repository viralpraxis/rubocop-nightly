# frozen_string_literal: true

module RuboCop
  module Nightly
    class Configuration
      # Builds a small set of configuration variants that, between them, exercise every
      # attribute value of every cop.
      #
      # Cops listed as dependencies of one another are explored jointly (cross product over
      # the cop plus its direct dependencies), so combinations that only misbehave together
      # are still produced. The resulting combinations are then packed into as few variants
      # as possible with a first-fit merge; first-fit is not guaranteed optimal (minimal set
      # cover is NP-hard) but is deterministic and cheap.
      class Traversal
        def self.call(cops, dependencies)
          new(cops, dependencies).generate
        end

        def initialize(cops, dependencies)
          @cops = cops
          @dependencies = dependencies
        end

        def generate
          minimize(required_combinations)
        end

        private

        attr_reader :cops, :dependencies

        def required_combinations
          seen = Set.new

          cops.each_key.flat_map do |cop_name|
            attribute_combinations(cop_name).select { seen.add?(it) }
          end
        end

        def attribute_combinations(cop_name)
          relevant = [cop_name, *Array(dependencies.fetch(cop_name, nil))]
          attributes = relevant.uniq.flat_map { |name| attributes_for(name) }.to_h

          return [{ cop_name => {} }] if attributes.empty?

          # The cop is pinned into every combination it generates. Without this, a cop that
          # has no configurable styles of its own but *does* have dependencies contributes
          # only its dependencies' keys, so it is never enabled by any variant and never
          # actually fuzzed.
          CoveringArray.call(attributes).map { nest(it).tap { |combo| combo[cop_name] ||= {} } }
        end

        # Keyed by [cop_name, attribute] tuples rather than an interpolated "cop.attribute"
        # string, which would be ambiguous for any name containing a dot.
        def attributes_for(name)
          declared = cops[name]
          return [] unless declared.is_a?(Hash)

          declared.filter_map do |attribute, values|
            values = Array(values)
            [[name, attribute], values] unless values.empty?
          end
        end

        def nest(flat_attributes)
          flat_attributes.each_with_object({}) do |((cop_name, attribute), value), nested|
            (nested[cop_name] ||= {})[attribute] = value
          end
        end

        # Two combinations can share a variant when they never disagree about the same
        # attribute of the same cop.
        def mergeable?(lhs, rhs)
          (lhs.keys & rhs.keys).all? do |cop_name|
            left = lhs.fetch(cop_name)
            right = rhs.fetch(cop_name)

            (left.keys & right.keys).all? { left.fetch(it) == right.fetch(it) }
          end
        end

        def merge(lhs, rhs)
          lhs.merge(rhs) { |_cop_name, left, right| left.merge(right) }
        end

        def minimize(combinations)
          combinations.each_with_object([]) do |combination, minimized|
            index = minimized.index { mergeable?(it, combination) }

            if index
              minimized[index] = merge(minimized[index], combination)
            else
              minimized << combination
            end
          end
        end
      end
    end
  end
end
