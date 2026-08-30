# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

module RuboCop
  module Nightly
    module Commands
      module Fuzzer
        # Decides what a variant's RuboCop invocation is actually pointed at.
        #
        # `--autocorrect` rewrites whatever it is given, and the corpus is a set of git checkouts
        # and extracted gems that every later run depends on: correcting it in place would corrupt
        # it permanently and silently change what the next night fuzzes. Correcting runs are
        # therefore pointed at throwaway copies and the corpus is only ever read, which is also
        # what makes the corrected source available for inspection afterwards.
        module Workspace
          def self.open(target_paths, autocorrect:, &)
            (autocorrect ? Ephemeral : ReadOnly).open(target_paths, &)
          end

          # Nothing is copied and nothing is corrected, so the paths handed to RuboCop are the
          # corpus paths themselves and there is no translation to do.
          class ReadOnly
            def self.open(target_paths, &) = yield(new(target_paths))

            def initialize(target_paths)
              @paths = target_paths
            end

            attr_reader :paths

            def rewritten = {}

            def original_for(path) = path
          end

          # Mirrors each target's absolute path under a temporary root, so that the basename and
          # the surrounding directories survive. Cops such as `RSpec/SpecFilePathFormat` and
          # `Naming/FileName` inspect the path itself, so flattening the corpus into one directory
          # would silently stop them from firing.
          class Ephemeral
            def self.open(target_paths, &)
              Dir.mktmpdir('rubocop-nightly-workspace') do |root|
                yield new(target_paths, root)
              end
            end

            def initialize(target_paths, root)
              @root = root
              @originals = materialize(target_paths)
            end

            def paths = originals.keys

            def original_for(path) = originals[path]

            # The copies RuboCop actually rewrote, paired with the corpus file each came from.
            # Compared byte by byte rather than by digest: most files come back untouched, and
            # `identical?` stops at the first differing byte instead of reading both files whole.
            def rewritten
              originals.select do |copy, original|
                !FileUtils.identical?(copy, original)
              rescue SystemCallError => e
                RuboCop::Nightly.logger.debug("Could not compare #{copy}: #{e.message}")
                false
              end
            end

            private

            attr_reader :root, :originals

            # A target that cannot be staged is dropped rather than fatal: one unreadable file in
            # a thousand-file batch must not cost the whole batch.
            def materialize(target_paths)
              target_paths.each_with_object({}) do |target_path, originals|
                original = File.expand_path(target_path)
                copy = File.join(root, original)

                FileUtils.mkdir_p(File.dirname(copy))
                FileUtils.copy_file(original, copy)
                # `copy_file` opens the destination with the source's mode, and gems ship
                # read-only files. Autocorrect has to be able to rewrite the copy.
                FileUtils.chmod('u+w', copy)

                originals[copy] = original
              rescue SystemCallError => e
                RuboCop::Nightly.logger.debug("Could not stage #{target_path}: #{e.message}")
              end
            end
          end
        end
      end
    end
  end
end
