# frozen_string_literal: true

require 'open3'

module RuboCop
  module Nightly
    module Runtime
      class << self
        def execute(*command, require_plugins: false)
          Bundler.with_original_env do
            Dir.chdir(RuboCop::Nightly::Runtime.gems_data_directory) do
              ENV['BUNDLE_GEMFILE'] = RuboCop::Nightly::Runtime.gems_data_directory.join('Gemfile').to_s

              Open3.capture3('bundle', 'exec', 'rubocop', *(plugin_requires_directive if require_plugins), *command)
            end
          end
        end

        def plugin_require_path(plugin_name) = gems_data_directory.join(plugin_name, 'lib', plugin_name).freeze

        def gems_data_directory = Pathname(data_directory.join('rubocop-gems')).freeze

        # FIXME: should be `~/.local/share/rubocop-nightly` by default;
        # blocked by https://github.com/rubocop/rubocop/issues/13676.
        # Maybe explicit top-level config `Include` should work?
        def data_directory
          Pathname(ENV.fetch('XDG_DATA_HOME', File.join(Dir.home, 'local', 'share'))).then do |path|
            path.join('rubocop-nightly').freeze
          end
        end

        private

        def plugin_requires_directive
          RuboCop::Nightly::Runtime::PluginRegistry
            .all_names
            .map { ['-r', it] }
            .flatten
        end
      end
    end
  end
end
