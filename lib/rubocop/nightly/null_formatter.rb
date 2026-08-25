# frozen_string_literal: true

# Loaded into RuboCop's own process via `--require`, so RuboCop is already present there.
# Required explicitly anyway to keep the file usable on its own (e.g. from specs).
require 'rubocop'

module RuboCop
  module Nightly
    # Discards all output: when fuzzing, only crashes reported on stderr matter.
    class NullFormatter < RuboCop::Formatter::BaseFormatter
      def started(*); end

      def file_started(*); end

      def file_finished(*); end

      def finished(*); end
    end
  end
end
