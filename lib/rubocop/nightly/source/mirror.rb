# frozen_string_literal: true

module RuboCop
  module Nightly
    module Source
      class Mirror
        def initialize(mirror_path:)
          @mirror_path = mirror_path
        end

        def fetch
          paths = @mirror_path.include?('*') ? Dir.glob(@mirror_path) : Dir.entries(@mirror_path)
          paths = paths.reject { it == '.' || it == '..' }
          paths = paths.map { |entry| File.join(@mirror_path, entry) }

          paths
        end
      end
    end
  end
end
