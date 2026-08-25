# frozen_string_literal: true

module RuboCop
  module Nightly
    module Commands
      module Fuzzer
        # Shrinks a crashing file to something a human can read.
        #
        # RuboCop's start-up dominates its runtime — inspecting 128 files costs the same as
        # inspecting one — so the oracle tests a whole round of candidates in a single subprocess.
        # That changes which algorithm is cheapest. Rather than delta debugging (which pays per
        # *round* and needs many rounds), each round asks "which single lines can be deleted?" in
        # one call, then speculatively deletes all of them at once in a second call. When the
        # speculation holds the input collapses geometrically; when it does not, one line still
        # goes, so progress is guaranteed.
        #
        # The line named in RuboCop's error message is pinned and never a deletion candidate, which
        # both keeps the trigger alive and shrinks the search space.
        class Reducer
          MAX_CANDIDATES = 240

          private_constant :MAX_CANDIDATES

          def initialize(oracle:, budget:)
            @oracle = oracle
            @budget = budget
          end

          def call(source, pinned_line:)
            lines = source.lines
            return source if lines.size <= 1

            pinned = pinned_index(lines, pinned_line)
            kept = lines.each_index.reject { it == pinned }

            until budget.exhausted?
              smaller = shrink(kept, lines, pinned)
              break unless smaller

              kept = smaller
            end

            render(lines, kept, pinned)
          end

          private

          attr_reader :oracle, :budget

          def pinned_index(lines, pinned_line)
            return nil unless pinned_line&.positive? && pinned_line <= lines.size

            pinned_line - 1
          end

          # Returns the next smaller keep-set, or nil when nothing more can be removed.
          def shrink(kept, lines, pinned)
            return nil if kept.empty?

            spans = removal_spans(kept)
            survivors = surviving_spans(spans, kept, lines, pinned)
            return nil if survivors.empty?

            speculate(kept, survivors, lines, pinned)
          end

          # Contiguous spans at every power-of-two size, not just single lines. Structure comes in
          # pairs — a `class` cannot go without its `end` — so single-line deletion stalls almost
          # immediately, while a span covering both succeeds. All sizes are tested in one call.
          def removal_spans(kept)
            spans = []
            size = kept.size

            while size >= 1
              kept.each_slice(size) { spans << it }
              break if size == 1

              size /= 2
            end

            spans.uniq.first(MAX_CANDIDATES)
          end

          def surviving_spans(spans, kept, lines, pinned)
            sources = spans.map { render(lines, kept - it, pinned) }

            oracle.select_reproducing(sources).map { spans[it] }
          end

          # Prefer the largest single removal, then try to delete every disjoint survivor at once;
          # when that holds the input collapses in one step instead of shrinking span by span.
          def speculate(kept, survivors, lines, pinned)
            best = survivors.max_by(&:size)
            union = disjoint_union(survivors)
            return kept - best if union.size <= best.size

            if oracle.select_reproducing([render(lines, kept - union, pinned)]).any?
              kept - union
            else
              kept - best
            end
          end

          def disjoint_union(survivors)
            survivors.sort_by { -it.size }.each_with_object([]) do |span, taken|
              taken.concat(span) unless taken.intersect?(span)
            end
          end

          def render(lines, kept, pinned)
            indices = pinned ? (kept + [pinned]) : kept

            indices.sort.map { lines[it] }.join
          end
        end
      end
    end
  end
end
