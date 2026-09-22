# frozen_string_literal: true

module RuboCop
  module Nightly
    module Source
      FNMATCH_FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH
      private_constant :FNMATCH_FLAGS

      Entry = Data.define(:path, :exclude) do
        def initialize(path:, exclude: [])
          super(path: path.to_s.chomp(File::SEPARATOR), exclude: Array(exclude).map(&:to_s).freeze)
        end

        def excludes?(candidate_path)
          return false if exclude.empty?

          ancestors(relative_path(candidate_path)).any? do |ancestor|
            exclude.any? { File.fnmatch?(it, ancestor, FNMATCH_FLAGS) }
          end
        end

        private

        def relative_path(candidate_path)
          return File.basename(candidate_path) if candidate_path == path

          candidate_path.delete_prefix("#{path}#{File::SEPARATOR}")
        end

        def ancestors(relative)
          segments = relative.split(File::SEPARATOR)

          segments.each_index.map { segments[0..it].join(File::SEPARATOR) }
        end
      end
    end
  end
end
