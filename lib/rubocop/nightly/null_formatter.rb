# frozen_string_literal: true

require 'rubocop'

module RuboCop
  module Nightly
    class NullFormatter < RuboCop::Formatter::BaseFormatter
      def started(*); end

      def file_started(*); end

      def file_finished(*); end

      def finished(*); end
    end
  end
end
