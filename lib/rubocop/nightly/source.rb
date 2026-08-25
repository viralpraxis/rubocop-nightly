# frozen_string_literal: true

module RuboCop
  module Nightly
    module Source
      TYPES = { rubygems: Rubygems, mirror: Mirror, git: Git }.freeze

      class << self
        def build(type, **)
          TYPES.fetch(type.to_sym) do
            raise ArgumentError, "unknown source #{type.inspect}, expected one of #{names.join(', ')}"
          end.new(**)
        end

        def names = TYPES.keys.map(&:to_s)
      end
    end
  end
end
