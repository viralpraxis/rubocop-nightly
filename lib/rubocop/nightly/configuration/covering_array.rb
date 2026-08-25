# frozen_string_literal: true

module RuboCop
  module Nightly
    class Configuration
      class Traversal
        # Builds the value combinations for a single cop (plus the cops it depends on).
        module CoveringArray
          module_function

          # A pairwise (2-wise) covering array rather than the full cross product.
          #
          # Exhaustively crossing one cop's own axes is what sets the number of variants, and
          # each variant costs a full RuboCop pass over the whole corpus. `Layout/HashAlignment`
          # alone (3 x 3 x 4) forced 36 variants; covering every *pair* of values instead needs
          # 12, and across RuboCop's real cop set the run drops from 36 variants to 20.
          # Configuration-dependent cop crashes essentially always hinge on one value or on one
          # pair of values, not on a specific 3-or-more-tuple, so this keeps the defect
          # detection while cutting the work.
          #
          # With fewer than two axes there are no pairs, so every value simply gets its own row.
          def call(attributes)
            return single_value_rows(attributes) if attributes.size < 2

            uncovered = required_pairs(attributes)
            rows = []

            while (row = next_row(attributes, uncovered))
              rows << row
            end

            rows
          end

          def single_value_rows(attributes)
            key, values = attributes.first

            values.map { { key => it } }
          end

          # Returns nil once nothing is left to cover — and also if a row would cover nothing,
          # which would otherwise loop forever.
          def next_row(attributes, uncovered)
            return nil if uncovered.empty?

            row = greedy_row(attributes, uncovered)
            covered = uncovered.select { |pair| satisfies?(row, pair) }
            return nil if covered.empty?

            uncovered.subtract(covered)
            row
          end

          def required_pairs(attributes)
            attributes.keys.combination(2).flat_map do |left, right|
              attributes[left].product(attributes[right]).map { [left, it[0], right, it[1]] }
            end.to_set
          end

          # Builds one row by choosing, for each axis in turn, the value that covers the most
          # still-uncovered pairs given the choices already made. Deterministic: `max_by` keeps
          # the first maximum and the axes are visited in declaration order.
          def greedy_row(attributes, uncovered)
            attributes.each_with_object({}) do |(key, values), row|
              row[key] = values.max_by { |value| newly_covered(row, key, value, uncovered) }
            end
          end

          # Counts uncovered pairs that (key => value) participates in and that are still
          # reachable given the choices already made. Scoring fully-satisfied pairs instead
          # would score every candidate for the first axis at zero — no pair can be satisfied
          # until both of its axes are assigned — leaving the search unable to make progress.
          def newly_covered(row, key, value, uncovered)
            uncovered.count { |pair| reachable?(row, key, value, pair) }
          end

          def reachable?(row, key, value, (left, left_value, right, right_value))
            if left == key
              left_value == value && [nil, right_value].include?(row[right])
            elsif right == key
              right_value == value && [nil, left_value].include?(row[left])
            else
              false
            end
          end

          def satisfies?(row, (left, left_value, right, right_value))
            row[left] == left_value && row[right] == right_value
          end
        end
      end
    end
  end
end
