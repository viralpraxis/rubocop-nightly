# frozen_string_literal: true

module RuboCop
  module Nightly
    module Commands
      class Compare
        class Report
          Offense = Data.define(:cop_name, :location, :message) do
            def eql?(other) = cop_name == other.cop_name && location == other.location
            def hash = [cop_name, location].hash
          end

          private_class_method :new

          def self.call(...)
            new(...)
          end

          attr_reader :removed_offenses, :new_offenses, :source_directory_path

          def initialize(offenses_before, offenses_after, source_directory_path:)
            offenses_before = plain_report_to_hashmap(offenses_before)
            offenses_after = plain_report_to_hashmap(offenses_after)

            @removed_offenses = find_offenses_difference(offenses_after, offenses_before)
            @new_offenses = find_offenses_difference(offenses_before, offenses_after)
            @source_directory_path = Pathname(source_directory_path)
          end

          private

          def find_offenses_difference(lhs, rhs)
            lhs.filter_map do |path, offenses|
              next if (offenses_difference = rhs.fetch(path) - offenses).empty?

              [path, offenses_difference]
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
