# frozen_string_literal: true

require 'digest'

module RuboCop
  module Nightly
    class Corpus
      RUBY_EXTENSIONS = %w[
        arb axlsx builder fcgi gemfile gemspec god jb jbuilder mspec opal pluginspec podspec
        rabl rake rb rbuild rbw rbx ru ruby schema simplecov spec thor watchr
      ].to_set.freeze

      RUBY_FILENAMES = %w[
        .irbrc .pryrc .simplecov Appraisals Berksfile Brewfile Buildfile Capfile Cheffile
        Dangerfile Deliverfile Fastfile Gemfile Guardfile Jarfile Mavenfile Podfile Puppetfile
        Rakefile Snapfile Steepfile Thorfile Vagabondfile Vagrantfile buildfile
      ].to_set.freeze

      def initialize(entries)
        @entries = Array(entries)
      end

      def files
        @files ||= begin
          expanded = expand
          unique = deduplicate(expanded)

          report(expanded.size, unique.size)
          unique
        end
      end

      private

      attr_reader :entries

      def expand
        entries.flat_map do |entry|
          if File.directory?(entry)
            Dir.glob(File.join(entry, '**', '*'), File::FNM_DOTMATCH).select { ruby_file?(it) }
          elsif ruby_file?(entry)
            [entry]
          else
            []
          end
        end.sort
      end

      def ruby_file?(path)
        return false unless File.file?(path)

        RUBY_EXTENSIONS.include?(File.extname(path).delete_prefix('.')) ||
          RUBY_FILENAMES.include?(File.basename(path))
      end

      def deduplicate(paths)
        paths.each_with_object({}) { |path, representatives| representatives[digest(path)] ||= path }.values
      end

      def digest(path)
        Digest::SHA256.file(path).hexdigest
      rescue SystemCallError => e
        RuboCop::Nightly.logger.debug "Could not hash #{path}: #{e.message}"
        path
      end

      def report(total, unique)
        return if total.zero?

        duplicates = total - unique
        share = (100.0 * duplicates / total).round(1)

        RuboCop::Nightly.logger.info(
          "Corpus: #{unique} distinct Ruby files from #{total} (#{duplicates} duplicates, #{share}% skipped)"
        )
      end
    end
  end
end
