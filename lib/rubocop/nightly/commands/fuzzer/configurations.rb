# frozen_string_literal: true

module RuboCop
  module Nightly
    module Commands
      module Fuzzer
        module Configurations
          module_function

          # Without `plugins` the run is confined to RuboCop's own cops: `--show-cops` is asked
          # for the core set alone, and the department filter then catches anything a plugin
          # might still have registered.
          def build(plugins: true, target_ruby_version: nil)
            Dir.chdir(Runtime.gems_data_directory) do
              Configuration.build(
                parser_engine: parser_engine_for(target_ruby_version), target_ruby_version:,
                remove_plugins: !plugins, keep_core_departments: !plugins
              )
            end
          rescue Errno::ENOENT
            raise ConfigurationError,
                  "RuboCop gems directory #{Runtime.gems_data_directory} does not exist — " \
                  'run `bundle exec rake gems:install` first'
          end

          def parser_engine_for(target_ruby_version)
            target_ruby_version ? 'default' : 'parser_prism'
          end

          def target_ruby_versions(requested)
            case requested
            when nil then [nil]
            when :all then supported_target_ruby_versions.empty? ? [nil] : supported_target_ruby_versions
            else validated_target_ruby_versions(requested)
            end
          end

          def validated_target_ruby_versions(requested)
            supported = supported_target_ruby_versions
            unknown = requested - supported
            return requested if supported.empty? || unknown.empty?

            raise ConfigurationError,
                  "unsupported target ruby version(s) #{unknown.join(', ')}, " \
                  "expected one of #{supported.join(', ')}"
          end

          def supported_target_ruby_versions
            Runtime.supported_target_ruby_versions(bundle_gemfile: Runtime.gems_data_directory.join('Gemfile'))
          end
        end
      end
    end
  end
end
