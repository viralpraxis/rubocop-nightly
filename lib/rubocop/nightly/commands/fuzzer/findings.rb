# frozen_string_literal: true

module RuboCop
  module Nightly
    module Commands
      module Fuzzer
        # Everything a run has learned so far, shared across batches so that a defect seen in one
        # batch is not reported again in every subsequent one.
        #
        # The kinds are kept apart rather than pooled into one bag because they do not mean the
        # same thing to a maintainer. The first three are bug reports; a Ruby warning is worth
        # reading but is not on its own a reason to fail the night, so only the first three move
        # the exit status.
        class Findings
          # `origin` is the emitting file with its Bundler revision hash masked out, so that the
          # same warning from two checkouts of the same gem is recognised as one warning.
          Warning = Data.define(:origin, :message) do
            def to_s = "#{origin}: #{message}"
          end

          # Paths are corpus paths throughout, never the throwaway copies a correcting run is
          # actually pointed at: those live in a directory that is gone by the time anyone reads
          # the report, and they differ on every run, which would defeat deduplication as well.
          CorrectionLoop = Data.define(:path, :cop_names) do
            def to_s = "#{path} (#{cop_names})"
          end

          BrokenCorrection = Data.define(:path, :diagnostic) do
            def to_s = "#{path}: #{diagnostic}"
          end

          def initialize
            @cop_errors = Set.new
            @correction_loops = Set.new
            @broken_corrections = Set.new
            @warnings = Set.new
          end

          attr_reader :cop_errors, :correction_loops, :broken_corrections, :warnings

          def defects = cop_errors.size + correction_loops.size + broken_corrections.size

          def empty? = defects.zero?

          def to_s
            format(
              '%<errors>d cop error(s), %<loops>d correction loop(s), %<broken>d broken ' \
              'correction(s), %<warnings>d Ruby warning(s)',
              errors: cop_errors.size, loops: correction_loops.size,
              broken: broken_corrections.size, warnings: warnings.size
            )
          end
        end
      end
    end
  end
end
