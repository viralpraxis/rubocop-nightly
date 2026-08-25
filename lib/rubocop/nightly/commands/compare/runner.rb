# frozen_string_literal: true

require 'json'
require 'tempfile'
require 'yaml'

module RuboCop
  module Nightly
    module Commands
      class Compare
        class Runner < Runner::Base
          DATA_DIR = Pathname(File.join(RuboCop::Nightly::Runtime.data_directory, 'compare')).freeze
          RUNTIME_DIR = DATA_DIR.join('runtime').freeze
          REPOSITORIES_DATA_DIR = DATA_DIR.join('repositories').freeze

          private_constant(*constants(false))

          class << self
            def call(source, from:, to:)
              source_directory_path = fetch_source_to_analyze(source)

              outcomes = [from, to].map { RevisionSpecification.parse(it) }.map do |runtime|
                run_rubocop(fetch_runtime(runtime), runtime, source_directory_path)
              end

              Report.call(*outcomes, source_directory_path:)
            end

            def fetch_source_to_analyze(source)
              specification = RevisionSpecification.parse(source, repository_only: true)
              directory = REPOSITORIES_DATA_DIR.join(specification.relative_path, specification.checkout_name)

              materialize(directory, specification, filter_blobs: true)
              directory
            end

            def fetch_runtime(runtime)
              directory = RUNTIME_DIR.join(runtime.relative_path, runtime.checkout_name)
              materialize(directory, runtime)

              Dir.chdir(directory) { system('bundle', 'install', exception: true, out: File::NULL) }
              RuboCop::Nightly.logger.info "Successfully prepared RuboCop #{runtime.describe}"

              directory
            end

            # Clones on first use and re-resolves the revision every run, so a branch tip
            # actually advances between runs and a cached checkout is never silently reused for
            # a different revision. Deliberately no `git pull`: after checking out a SHA or tag
            # the repository is in detached HEAD, where pull refuses to run and aborts the job.
            def materialize(directory, specification, filter_blobs: false)
              FileUtils.mkdir_p(directory.dirname)
              clone(directory, specification.repository, filter_blobs:) unless directory.join('.git').directory?

              Dir.chdir(directory) do
                system('git', 'fetch', '--force', '--tags', 'origin', exception: true, out: File::NULL)
                system('git', 'checkout', '--detach', resolve_revision(specification.revision),
                       exception: true, out: File::NULL)
              end
            end

            # `--filter=blob:none` skips historical blobs; the checkout still fetches what it
            # needs. `--branch` cannot be used because it rejects commit SHAs.
            def clone(directory, repository, filter_blobs: false)
              FileUtils.rm_rf(directory)
              arguments = %w[git clone]
              arguments.push('--filter=blob:none') if filter_blobs

              return if system(*arguments, '--', repository, directory.to_s, out: File::NULL)

              FileUtils.rm_rf(directory)
              system('git', 'clone', '--', repository, directory.to_s, exception: true, out: File::NULL)
            end

            def resolve_revision(revision)
              return 'origin/HEAD' if revision.nil?
              return "origin/#{revision}" if remote_branch?(revision)

              revision
            end

            def remote_branch?(revision)
              system('git', 'rev-parse', '--verify', '--quiet', "origin/#{revision}^{commit}",
                     out: File::NULL, err: File::NULL)
            end

            def run_rubocop(runtime_directory, runtime, source_directory_path)
              Dir.chdir(runtime_directory) do
                with_default_rubocop_configuration_file do |configuration_path|
                  stdout, stderr, status = Runtime.execute(
                    source_directory_path.to_s, '--cache', 'false',
                    '--format', 'json', '-c', configuration_path
                  )

                  RuboCop::Nightly.logger.warn(stderr) unless stderr.empty?
                  parse_report(stdout, stderr, status, runtime)
                end
              end
            end

            # RuboCop exits 1 when it merely finds offenses, which is the normal case here;
            # only a fatal error (2) or an unparseable report means the run cannot be trusted.
            def parse_report(stdout, stderr, status, runtime)
              raise ExecutionError, "RuboCop #{runtime.describe} failed: #{stderr.strip}" if status.exitstatus == 2

              JSON.parse(stdout)
            rescue JSON::ParserError => e
              raise ExecutionError, "RuboCop #{runtime.describe} produced an unparseable report: #{e.message}"
            end

            def with_default_rubocop_configuration_file(&)
              configuration = RuboCop::Nightly::Configuration.build(
                enable_all_cops: true, remove_plugins: true, keep_core_departments: true
              )

              with_temporary_file(configuration.to_yaml, &)
            end

            # Written through a handle that is flushed, closed and unlinked; the previous
            # `Tempfile.create.tap { it.write(...) }.path` left the data buffered and the
            # file on disk forever.
            def with_temporary_file(contents)
              file = Tempfile.create(['rubocop-nightly-compare', '.yml'])

              begin
                file.write(contents)
                file.flush
                yield file.path
              ensure
                file.close
                File.unlink(file.path)
              end
            end
          end
        end
      end
    end
  end
end
