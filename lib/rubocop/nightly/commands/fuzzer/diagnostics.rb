# frozen_string_literal: true

module RuboCop
  module Nightly
    module Commands
      module Fuzzer
        # Everything a variant's run said about itself, read back off stderr.
        #
        # RuboCop reports its three interesting failures three different ways: a cop that raises
        # while inspecting is announced and stepped over, a correction that never settles is
        # warned about and stepped over, and a Ruby warning is not RuboCop's doing at all. Only
        # the first has ever been read here, which is why the other two are parsed alongside it
        # rather than bolted onto the crash path.
        class Diagnostics
          ERROR_MESSAGE_REGEXP = /
            An\ error\ occurred\ while\ (?<cop_name>.+)\ cop\ was\ inspecting\ (?<source_pointer>.+?)\.?\z
          /x

          # The cause is the `->`-joined list of cops that kept undoing one another. Both halves
          # are optional: RuboCop omits the path when it has none.
          CORRECTION_LOOP_REGEXP = /
            Infinite\ loop\ detected(?:\ in\ (?<path>.+?))?(?:\ and\ caused\ by\ (?<cop_names>.*))?\z
          /x

          # `<file>:<line>: warning: <message>`, which is how Ruby formats every warning it emits.
          WARNING_REGEXP = /\A(?<origin>.+?):\d+:(?:in\ .+?:)?\s*warning:\s*(?<message>.+)\z/

          # Bundler keeps one checkout per revision, so without masking the revision the same
          # warning from two checkouts of one gem looks like two findings.
          CHECKOUT_REVISION = %r{-\h{7,}(?=/)}

          # RuboCop colours its stderr whenever it believes it is on a terminal.
          ANSI_ESCAPE = /\e\[[0-9;]*m/

          private_constant :ERROR_MESSAGE_REGEXP, :CORRECTION_LOOP_REGEXP, :WARNING_REGEXP,
                           :CHECKOUT_REVISION, :ANSI_ESCAPE

          Parsed = Data.define(:cop_errors, :correction_loops, :warnings)

          def self.parse(...) = new(...).parse

          def initialize(stderr, workspace:)
            @lines = stderr.to_s.gsub(ANSI_ESCAPE, '').split("\n")
            @workspace = workspace
          end

          def parse = Parsed.new(cop_errors:, correction_loops:, warnings:)

          private

          attr_reader :lines, :workspace

          def cop_errors
            lines.grep(/An error occurred/).uniq.filter_map { parse_cop_error(it) }.uniq
          end

          def parse_cop_error(line)
            match = line.strip.match(ERROR_MESSAGE_REGEXP)

            unless match
              RuboCop::Nightly.logger.debug("Unrecognised RuboCop error line: #{line}")
              return nil
            end

            translate(ErrorDetails.new(cop_name: match[:cop_name], source_pointer: match[:source_pointer]))
          end

          # A correcting run names the throwaway copy it was pointed at. Reporting that would hand
          # over a path that no longer exists by the time anyone reads the log and — because the
          # directory is new on every run — would defeat deduplication across batches entirely.
          def translate(error_detail)
            original = workspace.original_for(error_detail.path)
            return error_detail if original.nil? || original == error_detail.path

            ErrorDetails.new(
              cop_name: error_detail.cop_name,
              source_pointer: error_detail.source_pointer.sub(error_detail.path, original)
            )
          end

          def correction_loops
            lines.grep(/Infinite loop detected/).uniq.filter_map { parse_correction_loop(it) }
          end

          def parse_correction_loop(line)
            match = line.strip.match(CORRECTION_LOOP_REGEXP)
            return nil unless match

            Findings::CorrectionLoop.new(
              path: workspace.original_for(match[:path]) || match[:path],
              cop_names: match[:cop_names].to_s
            )
          end

          def warnings = lines.filter_map { parse_warning(it) }

          def parse_warning(line)
            match = line.match(WARNING_REGEXP)
            return nil unless match

            Findings::Warning.new(origin: mask_origin(match[:origin]), message: match[:message])
          end

          def mask_origin(origin)
            origin.delete_prefix("#{Runtime.gems_data_directory}/").sub(CHECKOUT_REVISION, '')
          end
        end
      end
    end
  end
end
