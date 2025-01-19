# frozen_string_literal: true

module RuboCop
  module Nightly
    module Source
      class Mirror
        def initialize(mirror_path:)
          @mirror_path = mirror_path
        end

        def fetch
          Dir.entries(@mirror_path)
             .select { File.directory?("#{@mirror_path}/#{it}") && it != '.' && it != '..' }
             .map { "#{@mirror_path}/#{it}" }
        end
      end
    end
  end
end
