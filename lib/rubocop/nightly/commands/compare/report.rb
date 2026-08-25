# frozen_string_literal: true

module RuboCop
  module Nightly
    module Commands
      class Compare
        class Report
          # Identity is (cop, location) — the message is deliberately excluded so that pure
          # wording changes between two RuboCop revisions are not reported as regressions.
          # `==` is overridden alongside `eql?`/`hash` so every comparison agrees; Data's
          # generated `==` would otherwise also compare the message.
          Offense = Data.define(:cop_name, :location, :message) do
            def eql?(other) = other.is_a?(self.class) && cop_name == other.cop_name && location == other.location
            def ==(other) = eql?(other)
            def hash = [self.class, cop_name, location].hash
          end

          EMPTY_OFFENSES = Set.new.freeze
          private_constant :EMPTY_OFFENSES

          private_class_method :new

          def self.call(...)
            new(...)
          end

          attr_reader :removed_offenses, :new_offenses, :source_directory_path

          def initialize(offenses_before, offenses_after, source_directory_path:)
            before = plain_report_to_hashmap(offenses_before)
            after = plain_report_to_hashmap(offenses_after)

            # The two revisions do not necessarily inspect the same files, so iterate the
            # union: a file only one of them looked at still has to be reported.
            paths = before.keys | after.keys

            @removed_offenses = find_offenses_difference(paths, before, after)
            @new_offenses = find_offenses_difference(paths, after, before)
            @source_directory_path = Pathname(source_directory_path)
          end

          private

          def find_offenses_difference(paths, lhs, rhs)
            paths.filter_map do |path|
              difference = lhs.fetch(path, EMPTY_OFFENSES) - rhs.fetch(path, EMPTY_OFFENSES)

              [path, difference] unless difference.empty?
            end
          end

          def plain_report_to_hashmap(report)
            report.fetch('files').to_h { [it.fetch('path'), it.fetch('offenses').to_set { project_offense(it) }] }
          end

          def project_offense(offense)
            Offense.new(**offense.slice(*Offense.members.map(&:to_s)).transform_keys!(&:to_sym))
          end
        end
      end
    end
  end
end
