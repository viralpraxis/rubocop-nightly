# frozen_string_literal: true

module RuboCop
  module Nightly
    module Commands
      module Fuzzer
        # Turns what one variant's run said about itself into findings that survive the batch.
        #
        # Every kind is deduplicated against everything seen so far, because a defect is a property
        # of RuboCop rather than of the file that happened to reach it: one bug in a widely used
        # cop shows up in hundreds of corpus files, and reporting it once per file buries the
        # nineteen other bugs the same night found.
        class Reporter
          def initialize(findings:, target_paths:, reduce: false, autocorrect: false, only_show_types: nil)
            @findings = findings
            @target_paths = target_paths
            @reduce = reduce
            @autocorrect = autocorrect
            @only_show_types = only_show_types
          end

          def call(diagnostics, workspace, outcome)
            report_errors(diagnostics.cop_errors, outcome)
            report_correction_loops(diagnostics.correction_loops)
            report_warnings(diagnostics.warnings)
            report_broken_corrections(workspace, outcome)
          end

          private

          attr_reader :findings, :target_paths, :reduce, :autocorrect, :only_show_types

          # `--only-show-types` narrows the report, not the run: everything is still collected,
          # still deduplicated and still counted in the summary, so hiding a kind cannot quietly
          # turn a failing night green. The evidence is written either way, so widening the filter
          # on the next run does not mean re-fuzzing to get it back.
          def show?(finding) = only_show_types.nil? || only_show_types.include?(finding.issue_type)

          # The reproduction is persisted once for the whole variant, and only when it has
          # something new to say — it carries a copy of the configuration that produced it, which
          # runs to a couple of hundred kilobytes.
          def report_errors(cop_errors, outcome)
            unreported = cop_errors.reject { findings.cop_errors.include?(it) }
            return if unreported.empty?

            reproduction_path = Reproduction.persist(outcome, target_paths)

            unreported.each { report_error(it, outcome, reproduction_path) }
          end

          # The example is written before the line is logged, rather than after, so that the two
          # can share it. With `--reduce` that delays the line by however long shrinking takes.
          def report_error(error_detail, outcome, reproduction_path)
            findings.cop_errors.add(error_detail)
            # Every crash gets an MRE. `--reduce` only decides whether it is minimised first;
            # without it the example simply runs RuboCop against the whole offending file.
            mre = Reproduction.write_mre(error_detail, outcome.variant, reproduction_path, reduce:, autocorrect:)

            return unless show?(error_detail)

            RuboCop::Nightly.logger.error(
              "[#{error_detail.issue_type}] [#{reproduction_path}] " \
              "#{error_detail.cop_name}: #{error_detail.source_pointer} -> #{mre}"
            )
          end

          def report_correction_loops(correction_loops)
            correction_loops.each do |correction_loop|
              next unless findings.correction_loops.add?(correction_loop)
              next unless show?(correction_loop)

              RuboCop::Nightly.logger.error("[#{correction_loop.issue_type}] #{correction_loop}")
            end
          end

          def report_warnings(warnings)
            warnings.each do |warning|
              next unless findings.warnings.add?(warning)

              RuboCop::Nightly.logger.warn("Ruby warning: #{warning}")
            end
          end

          # The target version is read back off the variant rather than recomputed, so a correction
          # is judged against the grammar RuboCop was actually told to target.
          def report_broken_corrections(workspace, outcome)
            return unless autocorrect

            unreported = unreported_broken_corrections(workspace, outcome.variant)
            return if unreported.empty?

            reproduction_path = Reproduction.persist(outcome, target_paths)
            corrected = workspace.rewritten.to_h { |copy, original| [original, copy] }

            unreported.each { report_broken_correction(it, corrected, reproduction_path) }
          end

          def unreported_broken_corrections(workspace, variant)
            CorrectionCheck.call(
              workspace.rewritten, target_ruby_version: variant.dig('AllCops', 'TargetRubyVersion')
            ).reject { findings.broken_corrections.include?(it) }
          end

          def report_broken_correction(broken_correction, corrected, reproduction_path)
            findings.broken_corrections.add(broken_correction)
            mre = BrokenCorrectionReport.write(
              broken_correction, corrected[broken_correction.path], reproduction_path
            )

            return unless show?(broken_correction)

            RuboCop::Nightly.logger.error(
              "[#{broken_correction.issue_type}] [#{reproduction_path}] #{broken_correction} -> #{mre}"
            )
          end
        end
      end
    end
  end
end
