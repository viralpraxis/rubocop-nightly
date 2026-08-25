# frozen_string_literal: true

module RuboCop
  module Nightly
    module Commands
      module Fuzzer
        # Identifies *which* crash we are looking at, so reduction cannot silently converge on a
        # different bug.
        #
        # The exception message embeds source offsets — the same defect reports
        # "The range 14...15 is outside the bounds of the source" before reduction and
        # "The range 37...38 ..." after a line is removed. Comparing raw messages would therefore
        # reject every successful reduction, so digit runs are masked before comparison.
        CAUSE_LINE = /^Error: cause: #<(?<klass>[A-Z][\w:]*): (?<message>.*)>/

        Signature = Data.define(:cop_name, :exception_class, :masked_message) do
          class << self
            # Parses the output of a `--raise-cop-error` run, or nil when it did not crash.
            # Returning a "we crashed but do not know how" value instead would be worse than
            # useless: such a signature matches everything, including a clean run, which silently
            # turns "could not isolate this" into "reduced it to itself".
            def parse(output, cop_name:)
              match = output.match(CAUSE_LINE)
              return nil unless match

              new(cop_name:, exception_class: match[:klass], masked_message: mask(match[:message]))
            end

            def mask(message) = message.gsub(/\d+/, 'N')
          end

          def matches?(other)
            return false unless other

            cop_name == other.cop_name &&
              exception_class == other.exception_class &&
              masked_message == other.masked_message
          end

          def describe = "#{cop_name} (#{exception_class})"

          def slug = "#{cop_name.tr('/', '-')}-#{exception_class}"
        end

        private_constant :CAUSE_LINE
      end
    end
  end
end
