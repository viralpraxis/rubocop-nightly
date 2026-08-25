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
          FileUtils.mkdir_p(DATA_DIRECTORY)

          Array(sources).filter_map do |source|
            unless source.is_a?(Hash) && source['url']
              raise ConfigurationError, "git source entry must be a mapping with a 'url' key, got #{source.inspect}"
            end

            process_git_source(git_url: source.fetch('url'), branch: source.fetch('branch', nil))
          end
        end

        private

        attr_reader :sources

        # Nightly runs are worthless against a snapshot frozen on the day of the first clone,
        # so an existing checkout is fast-forwarded to the current branch tip.
        def process_git_source(git_url:, branch:)
          repository_path = DATA_DIRECTORY.join(directory_name_for(git_url))

          if repository_path.join('.git').directory?
            update(repository_path, branch)
          else
            clone(repository_path, git_url, branch)
          end
        end

        def clone(repository_path, git_url, branch)
          FileUtils.rm_rf(repository_path)
          arguments = ['git', 'clone', '--depth', '1']
          arguments.push('--branch', branch) if branch

          _stdout, stderr, status = Open3.capture3(*arguments, '--', git_url, repository_path.to_s)
          return repository_path.to_s if status.success?

          # A failed clone used to leave a path that does not exist to be handed to RuboCop.
          RuboCop::Nightly.logger.error("Failed to clone #{git_url}; skipping. #{stderr.strip}")
          FileUtils.rm_rf(repository_path)
          nil
        end

        def update(repository_path, branch)
          Dir.chdir(repository_path) do
            unless fast_forward(branch)
              RuboCop::Nightly.logger.warn("Failed to update #{repository_path}; using the existing checkout")
            end
          end

          repository_path.to_s
        end

        def fast_forward(branch)
          arguments = ['git', 'fetch', '--depth', '1', 'origin', *branch]

          system(*arguments, out: File::NULL, err: File::NULL) &&
            system('git', 'reset', '--hard', 'FETCH_HEAD', out: File::NULL)
        end

        # `basename` alone collides across organisations (ruby/spec and rspec/spec) and keeps
        # the `.git` suffix in the directory name.
        def directory_name_for(git_url)
          git_url
            .sub(%r{\A[a-z][a-z0-9+.-]*://}i, '')
            .sub(/\A[\w.-]+@/, '')
            .delete_suffix('.git')
            .gsub(/[^\w.-]+/, '_')
            .gsub(/\.{2,}/, '_')
        end
      end
    end
  end
end
