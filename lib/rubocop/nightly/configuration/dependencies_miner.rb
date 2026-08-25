# frozen_string_literal: true

module RuboCop
  module Nightly
    class Configuration
      # Discovers, heuristically, which cops reference other cops by name — those pairs are
      # worth configuring together when fuzzing, because a bug may only surface when both
      # are enabled with particular styles.
      class DependenciesMiner
        COP_SOURCE_GLOB = 'ruby/*/bundler/gems/*/lib/rubocop/cop/**/*.rb'
        MIXIN_INCLUDE_PATTERN = /^\s*include\s+([A-Z][\w:]*)/

        def initialize(cop_names)
          @cop_names = cop_names
        end

        def mine
          return {}.freeze if sources_missing?

          cop_source_paths.each_with_object({}) do |cop_source_path, dependencies|
            cop_name = cop_name_for(cop_source_path)
            next unless cop_name

            referenced = referenced_cop_names(cop_source_path, cop_name)
            dependencies[cop_name] = referenced.freeze unless referenced.empty?
          end.freeze
        end

        private

        attr_reader :cop_names

        def sources_missing?
          return false unless cop_source_paths.empty?

          RuboCop::Nightly.logger.warn(
            "No cop sources found under #{RuboCop::Nightly::Runtime.gems_data_directory} " \
            '(has `rake gems:install` been run?); dependency mining is a no-op'
          )
          true
        end

        def referenced_cop_names(cop_source_path, cop_name)
          source = sources_for(cop_source_path).join("\n")

          cop_names.select do |candidate|
            next false if candidate == cop_name

            source.include?("'#{candidate}'") || source.include?("\"#{candidate}\"")
          end.to_set
        end

        # A cop frequently refers to other cops only through a shared mixin, so the mixin's
        # source counts as part of the cop's source for this heuristic.
        def sources_for(cop_source_path)
          source = read(cop_source_path)
          mixin_root = File.join(cop_source_path[%r{\A.*/lib/rubocop/cop/}].to_s, 'mixin')

          mixins = source.scan(MIXIN_INCLUDE_PATTERN).flatten.filter_map do |constant|
            path = File.join(mixin_root, "#{underscore(constant.split('::').last)}.rb")
            read(path) if File.file?(path)
          end

          [source, *mixins]
        end

        def read(path)
          File.read(path)
        rescue SystemCallError
          ''
        end

        # Deriving a cop name from its filename cannot be done reliably (acronyms, multi-word
        # departments, nested directories all break it). Matching against the authoritative
        # cop list from `rubocop --show-cops` instead is exact, and it also filters out
        # mixins, internal-affairs helpers and other non-cop files for free.
        def cop_name_for(cop_source_path)
          candidates = cop_names_by_basename[File.basename(cop_source_path, '.rb')]
          return if candidates.nil? || candidates.empty?
          return candidates.first if candidates.one?

          directory = normalize(File.basename(File.dirname(cop_source_path)))
          candidates.find { normalize(it.split('/')[-2].to_s) == directory }
        end

        def cop_names_by_basename
          @cop_names_by_basename ||= cop_names.group_by { underscore(it.split('/').last) }
        end

        def normalize(segment) = segment.downcase.delete('_')

        def underscore(name)
          name.gsub(/([A-Z\d]+)([A-Z][a-z])/, '\1_\2')
              .gsub(/([a-z\d])([A-Z])/, '\1_\2')
              .downcase
        end

        # Bundler keeps one checkout per revision, so an upgraded gem leaves its previous
        # checkouts behind. Keep only the most recently modified checkout of each gem,
        # otherwise stale sources silently win depending on glob order.
        def cop_source_paths
          @cop_source_paths ||= begin
            paths = Dir.glob(
              RuboCop::Nightly::Runtime.gems_data_directory.join(COP_SOURCE_GLOB),
              flags: File::FNM_DOTMATCH
            )

            paths.group_by { checkout_key(it) }
                 .values
                 .flat_map { |group| newest_checkout(group) }
          end
        end

        def checkout_key(path)
          checkout = path[%r{/bundler/gems/([^/]+)/}, 1].to_s

          [checkout.sub(/-\h{7,}\z/, ''), path[%r{/lib/rubocop/cop/(.*)\z}, 1]]
        end

        def newest_checkout(group)
          return group if group.one?

          [group.max_by { File.mtime(it) }]
        end
      end
    end
  end
end
