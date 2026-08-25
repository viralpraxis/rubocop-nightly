# frozen_string_literal: true

require 'digest'

module RuboCop
  module Nightly
    module Commands
      module Fuzzer
        # Everything needed to reproduce a cop crash outside the fuzzer, written somewhere
        # durable rather than into the working directory that is removed after the run.
        class Reproduction
          DIRECTORY = 'fuzzer/reproductions'

          private_constant :DIRECTORY

          def self.persist(...) = new(...).persist

          # Every crash gets its own directory, keyed by cop and by the exact location it was
          # reported at, so several crashes in one variant can never overwrite one another's
          # report — `RSpec/SpecFilePathFormat` alone hit seven different files in one batch.
          def self.write_mre(crash, variant, directory, reduce: false)
            target = directory.join('mre', slug(crash))
            FileUtils.mkdir_p(target)

            result = (reduce_crash(crash, variant) if reduce)
            result ? write_reduced(target, result) : write_whole_file(target, crash, variant)
          rescue StandardError => e
            RuboCop::Nightly.logger.warn("Could not write MRE for #{crash.cop_name}: #{e.class}: #{e.message}")
          end

          def self.slug(crash)
            "#{crash.cop_name.tr('/', '-')}-#{Digest::SHA256.hexdigest(crash.source_pointer)[0, 8]}"
          end

          # Reduction is best-effort and must never take down the run; a nil result simply
          # means the whole-file example is written instead.
          def self.reduce_crash(crash, variant)
            Reduction.call(crash, variant)
          rescue StandardError => e
            RuboCop::Nightly.logger.warn("Reduction failed for #{crash.cop_name}: #{e.class}: #{e.message}")
            nil
          end

          def self.write_reduced(target, result)
            File.write(target.join('mre.rb'), result.source)
            File.write(target.join('mre.yml'), result.configuration.to_yaml)
            write_script(target, result.command)

            RuboCop::Nightly.logger.info(summarize(result, target))
          end

          def self.summarize(result, target)
            "Reduced #{result.signature.describe} to #{result.source.lines.size} line(s) " \
              "from #{result.original_size} [#{result.budget}] -> #{target.join('mre.sh')}"
          end

          # Not minimal, but it always reproduces. The file is referenced rather than inlined:
          # an unreduced corpus file can be thousands of lines, and embedding it would make the
          # script unreadable for no benefit.
          def self.write_whole_file(target, crash, variant)
            return RuboCop::Nightly.logger.warn("No source file for #{crash.cop_name}") unless readable?(crash)

            configuration = MinimalConfiguration.new(variant, crash.cop_name)
            File.write(target.join('mre.yml'), configuration.to_yaml)
            write_script(target, whole_file_command(crash, configuration))

            RuboCop::Nightly.logger.info("Wrote whole-file MRE for #{crash.cop_name} -> #{target.join('mre.sh')}")
          end

          def self.readable?(crash) = crash.path && File.file?(crash.path)

          def self.whole_file_command(crash, configuration)
            [
              "# #{crash.cop_name} at #{crash.source_pointer}",
              "bundle exec rubocop --cache false --only #{crash.cop_name} --config <(cat <<'YAML'",
              configuration.to_yaml.delete_prefix("---\n").chomp,
              'YAML', ") #{crash.path}", ''
            ].join("\n")
          end

          # The self-contained form, used once the source has been reduced to a few lines.
          # Heredoc-based rather than `echo`: collapsing newlines changes what some cops see,
          # and at least one real crash stops reproducing when it is.
          def self.command(basename:, configuration_yaml:, source:)
            [
              "bundle exec rubocop --stdin #{basename} --config <(cat <<'YAML'",
              configuration_yaml.delete_prefix("---\n").chomp,
              'YAML', ") <<'RUBY'", source.chomp, 'RUBY', ''
            ].join("\n")
          end

          def self.write_script(target, body)
            target.join('mre.sh').tap do |path|
              File.write(path, body)
              File.chmod(0o755, path)
            end
          end

          def initialize(outcome, target_paths)
            @outcome = outcome
            @target_paths = target_paths
          end

          def persist
            FileUtils.mkdir_p(directory)
            contents.each { |name, body| File.write(directory.join(name), body) }

            directory
          end

          private

          attr_reader :outcome, :target_paths

          # Variant indices restart at zero for every batch, so the batch has to be part of
          # the name: otherwise a later batch overwrites an earlier batch's reproduction and
          # the crash it was reported for no longer has any evidence on disk. Digesting the
          # targets keeps it deterministic, so re-running the same batch reuses the directory.
          def directory
            @directory ||= Runtime.data_directory.join(
              DIRECTORY, "variant-#{outcome.index}-#{Digest::SHA256.hexdigest(target_paths.join("\n"))[0, 8]}"
            )
          end

          def contents
            {
              'configuration.yml' => File.read(outcome.configuration_path),
              'stdout.log' => outcome.stdout,
              'stderr.log' => outcome.stderr,
              'targets.txt' => "#{target_paths.join("\n")}\n"
            }
          end
        end
      end
    end
  end
end
