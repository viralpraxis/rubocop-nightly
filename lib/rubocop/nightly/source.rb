# frozen_string_literal: true

module RuboCop
  module Nightly
    module Source
      class << self
        def build(type, **)
          case type.to_sym
          when :rubygems then Rubygems
          when :mirror then Mirror
          when :git then Git
          else raise ArgumentError, type
          end.new(**)
        end
      end
    end
  end
end
