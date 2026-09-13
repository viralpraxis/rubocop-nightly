# frozen_string_literal: true

module RuboCop
  module Nightly
    module Commands
      module Fuzzer
        # Where a defect's runnable example ended up.
        #
        # Handed back to the reporter rather than logged where it is written, so that a defect and
        # the example reproducing it share a single line. A night that finds thirty defects
        # otherwise prints sixty lines whose halves have to be matched up by eye, and the halves do
        # not even stay adjacent once several variants are reporting.
        Mre = Data.define(:path, :detail) do
          class << self
            # The script is named relative to the reproduction directory that the same log line
            # already carries: spelling that prefix out twice doubles the length of the line and
            # tells the reader nothing new.
            def written(script, directory, detail = nil)
              new(path: script.relative_path_from(directory), detail: detail)
            end

            def failed(reason) = new(path: nil, detail: reason)
          end

          def to_s
            return "no MRE: #{detail}" unless path

            detail ? "#{path} (#{detail})" : path.to_s
          end
        end
      end
    end
  end
end
