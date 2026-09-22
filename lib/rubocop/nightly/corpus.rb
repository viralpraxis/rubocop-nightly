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
        @entries = Array(entries).map { it.is_a?(Source::Entry) ? it : Source::Entry.new(path: it) }
        @excluded = 0
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
        entries.flat_map { expand_entry(it) }.sort
      end

      def expand_entry(entry)
        candidates = candidates_for(entry)
        kept = candidates.reject { entry.excludes?(it) }
        @excluded += candidates.size - kept.size

        kept
      end

      def candidates_for(entry)
        if File.directory?(entry.path)
          Dir.glob(File.join(entry.path, '**', '*'), File::FNM_DOTMATCH).select { ruby_file?(it) }
        elsif ruby_file?(entry.path)
          [entry.path]
        else
          []
        end
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
        report_exclusions

        return if total.zero?

        duplicates = total - unique
        share = (100.0 * duplicates / total).round(1)

        RuboCop::Nightly.logger.info(
          "Corpus: #{unique} distinct Ruby files from #{total} (#{duplicates} duplicates, #{share}% skipped)"
        )
      end

      def report_exclusions
        return unless @excluded.positive?

        RuboCop::Nightly.logger.info("Corpus: #{@excluded} file(s) left out by source exclusions")
      end
    end
  end
end
