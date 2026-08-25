# frozen_string_literal: true

module RuboCop
  module Nightly
    module Commands
      class Compare
        def initialize(options)
          @options = options
        end

        # Returns true when the two revisions agree, so the CLI can exit non-zero on a
        # detected difference.
        def call
          Runner.call(options.source, from: options.from, to: options.to).then { present(it) }
        end

        private

        attr_reader :options, :source_directory_path

        def present(report)
          @source_directory_path = report.source_directory_path

          represent_report(report.removed_offenses, label: 'Removed offenses')
          represent_report(report.new_offenses, label: 'New offenses')

          unchanged = report.removed_offenses.empty? && report.new_offenses.empty?
          puts 'No offense differences between the two revisions.' if unchanged

          unchanged
        end

        def represent_report(offenses, label:)
          return if offenses.empty?

          puts <<~REPORT

            #{label}: (#{total_count(offenses)}):
            #{report_offenses(offenses)}
          REPORT
        end

        def report_offenses(offenses)
          offenses.map do |path, file_offenses|
            file_offenses.map do |offense|
              report_offense(path, offense)
            end.join("\n")
          end.join("\n")
        end

        def report_offense(path, offense)
          "[#{offense.cop_name}] #{prepare_path(path)}:#{prepare_location(offense.location)}: #{offense.message}"
        end

        # RuboCop reports absolute paths for targets outside its working directory, but falls
        # back to relative ones when they happen to be inside it.
        def prepare_path(path)
          pathname = Pathname(path)
          return pathname unless pathname.absolute?

          pathname.relative_path_from(source_directory_path)
        rescue ArgumentError
          pathname
        end

        def prepare_location(location)
          [location.fetch('line'), location.fetch('column')].join(':')
        end

        def total_count(offenses)
          offenses.sum { it.fetch(1).size }
        end
      end
    end
  end
end
