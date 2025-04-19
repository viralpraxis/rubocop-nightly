# frozen_string_literal: true

module RuboCop
  module Nightly
    class Configuration
      class DependenciesMiner
        def initialize(cop_names)
          @cop_names = cop_names
        end

        def mine # rubocop:disable Metrics
          dependencies = {}

          cop_source_paths.each do |cop_source_path|
            cop_source = File.read(cop_source_path)
            next unless cop_source.include?('< Base')

            cop_name = File.basename(cop_source_path).split('_').map(&:capitalize).join.delete_suffix('.rb')
            department_name = File.dirname(cop_source_path).split('/').last.capitalize
            qualified_cop_name = "#{department_name}/#{cop_name}"

            qualified_cop_name.tr! 'Rspec', 'RSpec' if qualified_cop_name.include?('Rspec')

            dependency_cop_names = cop_names.select do
              next if it == qualified_cop_name

              cop_source.include?("'#{it}'") || cop_source.include?("\"#{it}\"")
            end
            next if dependency_cop_names.empty?

            dependencies[qualified_cop_name] = dependency_cop_names.to_set.freeze
          end

          dependencies.freeze
        end

        private

        def cop_source_paths
          # FIXME: infer 3.4.0 from `RUBY_VERSION`
          @cop_source_paths ||=
            Dir.glob(
              RuboCop::Nightly::Runtime.gems_data_directory.join('ruby/3.4.0/bundler/gems/*/lib/rubocop/cop/**/*.rb'),
              flags: File::FNM_DOTMATCH
            )
        end

        attr_reader :cop_names
      end
    end
  end
end
