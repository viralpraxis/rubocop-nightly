# frozen_string_literal: true

module RuboCop
  module Nightly
    module Commands
      module Fuzzer
        # One cop crash as RuboCop reported it.
        #
        # Not every crash carries a location: path-based cops such as `RSpec/SpecFilePathFormat`
        # inspect the filename itself and report the bare path, so the location is optional and a
        # nil `line` simply means "nothing to pin during reduction".
        SOURCE_LOCATION = /:(?<line>\d+):(?<column>\d+)\z/

        ErrorDetails = Data.define(:cop_name, :source_pointer) do
          # How the line this ends up on is tagged. The other two kinds carry their own — between
          # them, `exception`, `broken-correction` and `infinite-loop` name every defect a run
          # reports, so a log can be filtered down to one kind of bug without parsing prose.
          def issue_type = 'exception'

          def path = source_pointer.sub(SOURCE_LOCATION, '')

          def line = source_pointer[SOURCE_LOCATION, 1]&.to_i
        end

        private_constant :SOURCE_LOCATION
      end
    end
  end
end
