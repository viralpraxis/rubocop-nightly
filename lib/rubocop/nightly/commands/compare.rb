# frozen_string_literal: true

module RuboCop
  module Nightly
    module Commands
      class Compare
        def initialize(options)
          @options = options
        end

        def call
          Runner.call(options.source, from: options.from, to: options.to).then do |report|
            @source_directory_path = report.source_directory_path

            represent_report(report.removed_offenses, label: 'Removed offenses')
            represent_report(report.new_offenses, label: 'New offenses')
          end
        end

        private

        attr_reader :options, :source_directory_path

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

        def prepare_path(path)
          Pathname(path).relative_path_from(source_directory_path)
        end

        def prepare_location(location)
          [location.fetch('line'), location.fetch('column')].join(':')
        end

        def total_count(offenses)
          offenses.map { it.fetch(1) }.sum(&:size)
        end
      end
    end
  end
end
