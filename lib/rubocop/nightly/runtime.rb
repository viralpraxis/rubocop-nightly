# frozen_string_literal: true

require 'open3'

module RuboCop
  module Nightly
    module Runtime
      CORE_DEPARTMENTS = %w[AllCops Bundler Layour Metrics Naming Security Style Lint].to_set.freeze

      class << self
        def execute(
          *command,
          require_plugins: false,
          bundle_gemfile: Pathname(Dir.pwd).join('Gemfile')
        )
          Open3.capture3(
            { 'BUNDLE_GEMFILE' => bundle_gemfile.to_s },
            'bundle',
            'exec',
            'rubocop',
            *(plugin_requires_directive if require_plugins),
            *command
          )
        end

        def plugin_require_path(plugin_name) = gems_data_directory.join(plugin_name, 'lib', plugin_name).freeze

        def gems_data_directory = Pathname(data_directory.join('rubocop-gems')).freeze

        def data_directory
          Pathname(ENV.fetch('XDG_DATA_HOME', File.join(Dir.home, '.local', 'share'))).then do |path|
            path.join('rubocop-nightly').freeze
          end
        end

        def rubocop_repository_uri = 'https://github.com/rubocop/rubocop.git'

        private

        def plugin_requires_directive
          RuboCop::Nightly::Runtime::PluginRegistry
            .all_names
            .map { ['--plugin', it] }
            .flatten
        end
      end
    end
  end
end
