# frozen_string_literal: true

module RuboCop
  module Nightly
    module Source
      class Mirror
        def initialize(mirror_path:)
          @mirror_path = mirror_path
        end

        # Whatever the path names is handed over as it stands. `Corpus` already walks a directory
        # recursively and keeps only the Ruby files out of it, so selecting here can only lose
        # things: this used to descend one level and keep the directories alone, which analysed
        # nothing at all when the path held loose `.rb` files rather than one directory per gem.
        def fetch
          return Dir.glob(mirror_path) if mirror_path.include?('*')

          ensure_directory!
          [mirror_path]
        end

        private

        attr_reader :mirror_path

        def ensure_directory!
          return if File.directory?(mirror_path)

          raise ConfigurationError, "mirror path #{mirror_path.inspect} is not a directory"
        end
      end
    end
  end
end
