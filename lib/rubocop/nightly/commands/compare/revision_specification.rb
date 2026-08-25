# frozen_string_literal: true

module RuboCop
  module Nightly
    module Commands
      class Compare
        # Parses the `--from` / `--to` / `--source` arguments, each of which is one of:
        #
        #   53e5d198f                                  a revision of RuboCop itself
        #   https://github.com/rails/rails.git         a repository at its default branch
        #   https://github.com/rails/rails.git:main    a repository at an explicit revision
        #   git@github.com:rubocop/rubocop.git:master  the same, scp-style
        #
        # The previous implementation discriminated on the substring `'.git:'`, so a plain
        # repository URL was treated as a bare revision and silently replaced with RuboCop's
        # own repository.
        class RevisionSpecification
          REPOSITORY = %r{\A(?:[a-z][a-z0-9+.-]*://|[\w.-]+@[\w.-]+:)}i
          SCHEME = %r{\A[a-z][a-z0-9+.-]*://}i
          SCP_PREFIX = /\A[\w.-]+@[\w.-]+:/

          private_constant(:REPOSITORY, :SCHEME, :SCP_PREFIX)

          attr_reader :repository, :revision

          def self.parse(specification, repository_only: false)
            new(specification, repository_only:)
          end

          def initialize(specification, repository_only: false)
            if REPOSITORY.match?(specification)
              @repository, @revision = split(specification)
            elsif repository_only
              raise ArgumentError, "#{specification.inspect} is not a repository URL"
            else
              @repository = RuboCop::Nightly::Runtime.rubocop_repository_uri
              @revision = specification
            end
          end

          # Filesystem-safe, and keyed by revision so two revisions of the same repository can
          # never share (and clobber) one checkout.
          def checkout_name = (revision || 'default').gsub(/[^\w.-]/, '_')

          def relative_path
            (path_component(repository) || repository)
              .delete_suffix('.git')
              .gsub(%r{[^\w./-]}, '_')
              .gsub(/\.{2,}/, '_')
          end

          def describe = "#{repository}@#{revision || 'default branch'}"

          private

          # Only a colon in the *path* component separates a revision, so neither
          # `https://host:8080/o/r.git` nor `git@host:o/r.git` is mis-split.
          def split(specification)
            path = path_component(specification)
            index = path&.rindex(':')
            return [specification, nil] unless index

            revision = path[(index + 1)..]
            return [specification, nil] if revision.empty? || revision.include?('/')

            [specification[0...(specification.length - revision.length - 1)], revision]
          end

          def path_component(specification)
            if (scheme = specification[SCHEME])
              specification.delete_prefix(scheme).split('/', 2)[1]
            elsif (prefix = specification[SCP_PREFIX])
              specification.delete_prefix(prefix)
            end
          end
        end
      end
    end
  end
end
