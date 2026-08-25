# frozen_string_literal: true

module RuboCop
  module Nightly
    module Commands
      module Fuzzer
        # Everything needed to reproduce a cop crash outside the fuzzer, written somewhere
        # durable. RuboCop's stdout used to be discarded outright and the configuration lived
        # in a temporary directory that was removed moments later, so a reported crash left
        # nothing behind to investigate.
        class Reproduction
          DIRECTORY = 'fuzzer/reproductions'

          private_constant :DIRECTORY

          def self.persist(...) = new(...).persist

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

          def directory
            @directory ||= Runtime.data_directory.join(DIRECTORY, "variant-#{outcome.index}")
          end

          # `File.write` closes each handle, so every file is complete on disk.
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
