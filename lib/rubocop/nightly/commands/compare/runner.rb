# frozen_string_literal: true

require 'pathname'
require 'yaml'

module RuboCop
  module Nightly
    module Commands
      class Compare
        class Runner < Runner::Base
          DATA_DIR = Pathname(File.join(RuboCop::Nightly::Runtime.data_directory, 'compare')).freeze
          RUNTIME_DIR = DATA_DIR.join('runtime').freeze
          REPOSITORIES_DATA_DIR = DATA_DIR.join('repositores').freeze

          RemoteRuntime = Data.define(:repository, :revision, :relative_path)

          private_constant(*constants(false))

          class << self
            def call(source, from:, to:)
              FileUtils.mkdir_p(RUNTIME_DIR.to_s)

              source_directory_path = fetch_source_to_analyze(source)
              runtimes = [from, to].map { parse_revision_specification(it) }

              outcomes = runtimes.map do |runtime|
                fetch_runtime(runtime)
                run_rubocop(runtime, source_directory_path)
              end

              Report.call(*outcomes, source_directory_path:)
            end

            def fetch_source_to_analyze(source) # rubocop:disable Metrics/MethodLength
              revision = parse_revision_specification(source, revision_fallback: 'main')
              repository_directory = REPOSITORIES_DATA_DIR.join(revision.relative_path)
              FileUtils.mkdir_p(repository_directory)

              Dir.chdir(repository_directory) do
                unless File.exist?('.git')
                  system(
                    'git', 'clone', '--depth', '1', '--branch', revision.revision, revision.repository, '.',
                    exception: true, out: File::NULL
                  )
                end

                repository_directory
              end
            end

            # FIXME: switch to using different `remote` git objects?
            def fetch_runtime(runtime) # rubocop:disable Metrics/MethodLength
              FileUtils.mkdir_p(RUNTIME_DIR)
              Dir.chdir(RUNTIME_DIR) do
                unless File.exist?(runtime.relative_path)
                  system('git', 'clone', '--', runtime.repository, runtime.relative_path)
                end

                Dir.chdir(runtime.relative_path) do
                  system('git', 'fetch', exception: true, out: File::NULL)
                  system('git', 'checkout', runtime.revision, exception: true, out: File::NULL)
                  system('bundle', 'install', exception: true, out: File::NULL)

                  Nightly.logger.info "Successfully prepared RuboCop with revision #{runtime.revision}"
                end
              end
            end

            def create_default_rubocop_configuration_file
              configuration = RuboCop::Nightly::Configuration.build(
                enable_all_cops: true,
                remove_plugins: true,
                keep_core_departments: true
              )

              configuration
                .then(&:to_yaml)
                .then { |configuration_data| Tempfile.create.tap { |file| file.write(configuration_data) }.path }
            end

            def parse_revision_specification(revision_specification, revision_fallback: nil)
              repository, revision =
                if revision_specification.include?('.git:')
                  [revision_specification.split(':')[0..-2].join(':'), revision_specification.split(':')[-1]]
                else
                  [RuboCop::Nightly::Runtime.rubocop_repository_uri, revision_fallback || revision_specification]
                end

              RemoteRuntime.new(repository:, revision:, relative_path: relative_path_for_repository_url(repository))
            end

            def relative_path_for_repository_url(repository_url)
              URI(repository_url).path.sub(%r{^/}, '').sub(/\.git$/, '')
            end

            def run_rubocop(runtime, source_directory_path)
              Dir.chdir(RUNTIME_DIR.join(runtime.relative_path)) do
                rubocop_configuration_path = create_default_rubocop_configuration_file
                stdout, stderr, = Runtime.execute(
                  source_directory_path.to_s, '--cache',
                  'false', '--format',
                  'json', '-c', rubocop_configuration_path
                )

                RuboCop::Nightly.logger.warn(stderr) unless stderr.empty?
                JSON.parse(stdout)
              end
            end
          end
        end
      end
    end
  end
end
