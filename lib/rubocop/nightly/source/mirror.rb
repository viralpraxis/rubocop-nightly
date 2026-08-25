# frozen_string_literal: true

module RuboCop
  module Nightly
    module Source
      class Mirror
        def initialize(mirror_path:)
          @mirror_path = mirror_path
        end

        def fetch
          # `Dir.glob` already yields complete paths; only `Dir.children` needs the prefix
          # joined back on. Joining both was producing `<pattern><absolute-path>` strings
          # that could never exist.
          paths =
            if mirror_path.include?('*')
              Dir.glob(mirror_path)
            else
              ensure_directory!
              Dir.children(mirror_path).map { File.join(mirror_path, it) }
            end

          paths.select { File.directory?(it) }.sort
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
