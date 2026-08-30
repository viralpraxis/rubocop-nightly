# frozen_string_literal: true

require 'digest'

module RuboCop
  module Nightly
    module Commands
      module Fuzzer
        # A broken correction is the one finding whose evidence is destroyed the moment the variant
        # ends: the corrected file lives in the workspace's temporary directory. The corrected
        # source is copied out alongside a script that reruns the correction, so the bug can be
        # examined without first working out which of a few dozen variants produced it.
        module BrokenCorrectionReport
          module_function

          def write(finding, corrected_path, directory)
            target = directory.join('mre', slug(finding))
            FileUtils.mkdir_p(target)

            FileUtils.copy_file(corrected_path, target.join('corrected.rb'))
            Reproduction.write_script(target, command(finding, directory))

            RuboCop::Nightly.logger.info(
              "Wrote broken-correction MRE for #{finding.path} -> #{target.join('mre.sh')}"
            )
          rescue StandardError => e
            RuboCop::Nightly.logger.warn("Could not write MRE for #{finding.path}: #{e.class}: #{e.message}")
          end

          def slug(finding)
            "broken-correction-#{File.basename(finding.path, '.rb')}-" \
              "#{Digest::SHA256.hexdigest(finding.path)[0, 8]}"
          end

          # The variant configuration is referenced rather than copied: it runs to a couple of
          # hundred kilobytes, and `Reproduction.persist` has already written one copy per variant.
          # The correction is rerun against a scratch copy so that replaying the MRE cannot rewrite
          # the corpus file it came from.
          def command(finding, directory)
            [
              "# #{finding.path}: #{finding.diagnostic}",
              '# `corrected.rb` alongside this script is the output that failed to parse.',
              'copy=$(mktemp /tmp/rubocop-nightly-broken-XXXXXX.rb)',
              %(cp #{finding.path} "$copy"),
              'bundle exec rubocop --autocorrect-all --cache false \\',
              %(  --config #{directory.join('configuration.yml')} "$copy"),
              parse_check,
              ''
            ].join("\n")
          end

          def parse_check
            %(ruby -rprism -e 'r = Prism.parse_file(ARGV[0]); ) +
              %(puts(r.success? ? "corrected source parses" : r.errors.first.message)' "$copy")
          end
        end
      end
    end
  end
end
