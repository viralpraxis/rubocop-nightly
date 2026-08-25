# frozen_string_literal: true

require 'digest'

module RuboCop
  module Nightly
    # Expands the entries a source yields (gem directories, repository checkouts, plain files)
    # into the individual Ruby files to inspect, dropping files whose content has already been
    # seen.
    #
    # Parsing is the dominant cost of a fuzzing run and corpora repeat themselves heavily: a
    # gem published for ten platforms ships ten byte-identical copies of its library, and
    # vendored files recur across gems. On a 50-gem sample of rubygems.org, 17,613 Ruby files
    # collapse to 6,541 distinct ones — 62.9% of the parsing was redundant.
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

      # Filtering by name before hashing keeps the digest pass off git packfiles and other
      # large non-Ruby content that a repository checkout drags along.
      def ruby_file?(path)
        return false unless File.file?(path)

        RUBY_EXTENSIONS.include?(File.extname(path).delete_prefix('.')) ||
          RUBY_FILENAMES.include?(File.basename(path))
      end

      def deduplicate(paths)
        paths.each_with_object({}) { |path, representatives| representatives[digest(path)] ||= path }.values
      end

      # An unreadable file is kept rather than dropped: inspecting it and letting RuboCop
      # report the problem is more useful than silently removing it from the corpus.
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
