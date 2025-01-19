# frozen_string_literal: true

module RuboCop
  module Nightly
    module Source
      class Git
        DATA_DIRECTORY = Runtime.data_directory.join('git').freeze
        private_constant(*constants(false))

        def initialize(sources:)
          @sources = sources
        end

        def fetch
          sources.map do |source|
            git_url = source.fetch('url')
            branch = source.fetch('branch')
            name = git_url.split('/').last

            FileUtils.mkdir_p(DATA_DIRECTORY)

            process_git_source(git_url:, branch:, name:)
          end
        end

        private

        attr_reader :sources

        def process_git_source(git_url:, branch:, name:)
          Dir.chdir(DATA_DIRECTORY) do |path|
            repository_path = Pathname(path).join(name)

            unless File.exist?(repository_path)
              system('git', 'clone', '--depth', '1', '--branch', branch, git_url, name)
            end

            repository_path.to_s
          end
        end
      end
    end
  end
end
