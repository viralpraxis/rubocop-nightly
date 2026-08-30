# frozen_string_literal: true

module RuboCop
  module Nightly
    module Commands
      module Fuzzer
        # The strongest oracle the fuzzer has: source that parsed before `--autocorrect` and does
        # not parse after it is a bug, with no judgement call to make and no reproduction to
        # assemble by hand. RuboCop does not check this itself — it writes the corrected file out
        # either way, so a broken correction reaches the user's working tree.
        #
        # The check is deliberately a *differential*. A file that already failed to parse is
        # skipped, so a disagreement between Prism and whatever engine RuboCop parsed the file
        # with can only ever cost a finding, never invent one.
        module CorrectionCheck
          module_function

          def call(rewritten, target_ruby_version:)
            return [] if rewritten.empty? || !prism_available?

            version = prism_version(target_ruby_version)

            rewritten.filter_map do |copy, original|
              diagnostic = diagnose(original, copy, version)

              Findings::BrokenCorrection.new(path: original, diagnostic:) if diagnostic
            end
          end

          def diagnose(original, copy, version)
            return nil unless parse(original, version)&.success?

            result = parse(copy, version)
            return nil if result.nil? || result.success?

            result.errors.first&.message || 'corrected source no longer parses'
          end

          def parse(path, version)
            Prism.parse_file(path, version: version)
          rescue SystemCallError, ArgumentError
            nil
          end

          def prism_available?
            require 'prism'
            true
          rescue LoadError
            RuboCop::Nightly.logger.warn('Prism is unavailable; corrected sources will not be checked')
            false
          end

          # Prism wants a full `x.y.z` while RuboCop's target is an `x.y` float, and it rejects a
          # version it does not know. Falling back to nil means "whatever grammar this Prism speaks",
          # which is a slightly newer one — better than skipping the check entirely.
          def prism_version(target_ruby_version)
            format('%.1f.0', target_ruby_version).tap { Prism.parse('', version: it) }
          rescue ArgumentError, TypeError
            nil
          end
        end
      end
    end
  end
end
