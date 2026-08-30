# frozen_string_literal: true

require 'tmpdir'

module RuboCop
  module Nightly
    module Commands
      module Fuzzer
        # Turns a raw crash into a minimal reproducible example: one cop, one tiny config, a few
        # lines of Ruby, and a command that runs it.
        class Reduction
          Result = Data.define(:signature, :source, :configuration, :basename, :original_size, :budget) do
            def reduced? = source.lines.size < original_size

            # Shared with the unreduced fallback so the two can never drift apart.
            def command
              Reproduction.command(basename:, configuration_yaml: configuration.to_yaml, source:)
            end
          end

          def self.call(...) = new(...).call

          def initialize(crash, variant, budget: nil, autocorrect: false)
            @crash = crash
            @variant = variant
            @budget = budget || Budget.new(seconds: 120, calls: 60)
            @autocorrect = autocorrect
          end

          # Returns nil when the crash cannot be reproduced in isolation at all — better to say
          # nothing than to hand over an example that does not work.
          def call
            return nil unless crash.path && File.file?(crash.path)

            configuration = MinimalConfiguration.new(variant, crash.cop_name)
            with_configuration_file(configuration) do |path|
              reduce(configuration, path)
            end
          end

          private

          attr_reader :crash, :variant, :budget, :autocorrect

          def reduce(configuration, configuration_path)
            signature = baseline_signature(configuration_path)
            return nil unless signature

            source = File.binread(crash.path)
            reduced = shrink(signature, configuration_path, source)

            build_result(signature, reduced, configuration, source)
          end

          # The reduced source is verified before it is handed back; an example that does not
          # reproduce is worse than none, so a failed check falls back to the original file.
          def shrink(signature, configuration_path, source)
            oracle = build_oracle(signature, configuration_path)
            reduced = Reducer.new(oracle:, budget:).call(source, pinned_line: crash.line)

            oracle.confirm(reduced) ? reduced : source
          end

          # Establishes both that the crash survives isolation and what its exception class is.
          # A nil result means the crash does not reproduce from this file and cop alone, and the
          # caller reports that honestly rather than emitting an example that does nothing.
          def baseline_signature(configuration_path)
            Dir.mktmpdir('rubocop-nightly-signature') do |root|
              path = File.join(root, basename)
              File.binwrite(path, File.binread(crash.path))

              Signature.parse(raise_cop_error(path, configuration_path), cop_name: crash.cop_name)
            end
          rescue ExecutionTimeout
            nil
          end

          # `--raise-cop-error` is what surfaces the exception class, which is how one crash is
          # told apart from a different bug in the same cop. It aborts on the first error, so it
          # can only ever check a single candidate.
          #
          # `--autocorrect` has to be mirrored here: a crash raised from a cop's corrector does not
          # happen at all on a read-only pass, and the baseline would come back clean — which the
          # caller reads as "does not reproduce in isolation" and abandons the reduction.
          def raise_cop_error(path, configuration_path)
            stdout, stderr, _status = Runtime.execute(
              path, '--cache', 'false', '--format', 'quiet', '--raise-cop-error',
              '--config', configuration_path.to_s, *('--autocorrect' if autocorrect),
              require_plugins: true, timeout: budget.per_call_timeout,
              bundle_gemfile: Runtime.gems_data_directory.join('Gemfile')
            )

            "#{stdout}#{stderr}"
          end

          def build_oracle(signature, configuration_path)
            Oracle.new(signature:, configuration_path:, basename:, budget:, autocorrect:)
          end

          def build_result(signature, reduced, configuration, source)
            Result.new(
              signature:, source: reduced, configuration:, basename:,
              original_size: source.lines.size, budget:
            )
          end

          def with_configuration_file(configuration)
            Dir.mktmpdir('rubocop-nightly-config') do |root|
              path = File.join(root, 'config.yml')
              File.write(path, configuration.to_yaml)

              yield path
            end
          end

          def basename = @basename ||= File.basename(crash.path)
        end
      end
    end
  end
end
