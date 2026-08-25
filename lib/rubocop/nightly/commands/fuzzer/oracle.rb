# frozen_string_literal: true

require 'tmpdir'

module RuboCop
  module Nightly
    module Commands
      module Fuzzer
        # Answers "does this source still crash the same cop the same way?".
        #
        # RuboCop's start-up dominates its runtime: inspecting 128 files costs the same 0.54s as
        # inspecting one. Candidates are therefore written side by side and tested in a *single*
        # invocation, which is what makes delta debugging affordable — one subprocess per round
        # rather than one per candidate.
        class Oracle
          ERROR_LINE = /An error occurred while (?<cop_name>\S+) cop was inspecting (?<path>.+?):\d+:\d+/
          private_constant :ERROR_LINE

          def initialize(signature:, configuration_path:, basename:, budget:, autocorrect: false)
            @signature = signature
            @configuration_path = configuration_path
            @basename = basename
            @budget = budget
            @autocorrect = autocorrect
          end

          # Returns the indices of the candidates that reproduced. One subprocess for all of them.
          def select_reproducing(candidates)
            return [] if candidates.empty? || !budget.claim!

            Dir.mktmpdir('rubocop-nightly-reduce') do |root|
              paths = materialize(root, candidates)
              _stdout, stderr, _status = run(root)

              crashed = crashed_paths(stderr)
              paths.filter_map { |path, index| index if crashed.include?(path) }
            end
          end

          # Strict, single-candidate check: `--raise-cop-error` reports the exception class, which
          # is what distinguishes this crash from a different bug in the same cop. It aborts on the
          # first error, so it cannot be batched — it is the checkpoint, not the search.
          def confirm(source)
            return false unless budget.claim!(mandatory: true)

            Dir.mktmpdir('rubocop-nightly-confirm') do |root|
              path = File.join(root, basename)
              File.binwrite(path, source)
              stdout, stderr, _status = run(path, '--raise-cop-error')

              signature.matches?(Signature.parse("#{stdout}#{stderr}", cop_name: signature.cop_name))
            end
          end

          private

          attr_reader :signature, :configuration_path, :basename, :budget, :autocorrect

          # The basename is preserved for every candidate: cops such as `RSpec/ExampleWording` only
          # apply to paths matching `*_spec.rb`, so renaming the file silently stops the crash.
          def materialize(root, candidates)
            candidates.each_with_index.to_h do |source, index|
              directory = File.join(root, index.to_s)
              FileUtils.mkdir_p(directory)
              path = File.join(directory, basename)
              File.binwrite(path, source)

              [path, index]
            end
          end

          # `bundle_gemfile` is passed explicitly rather than relying on the caller's working
          # directory: the plugins named by `require_plugins` only exist in the gems bundle.
          def run(target, *extra)
            Runtime.execute(
              target.to_s, '--cache', 'false', '--format', 'quiet',
              '--config', configuration_path.to_s, *('--autocorrect' if autocorrect), *extra,
              require_plugins: true, timeout: budget.per_call_timeout,
              bundle_gemfile: Runtime.gems_data_directory.join('Gemfile')
            )
          rescue ExecutionTimeout
            ['', '', nil]
          end

          def crashed_paths(stderr)
            stderr.to_s.scan(ERROR_LINE).filter_map do |cop_name, path|
              path if cop_name == signature.cop_name
            end.to_set
          end
        end
      end
    end
  end
end
