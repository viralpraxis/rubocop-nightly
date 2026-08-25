# frozen_string_literal: true

require 'net/http'
require 'json'
require 'digest'
require 'fileutils'
require 'tmpdir'
require 'date'
require 'rubygems/package'

module RuboCop
  module Nightly
    module Source
      class Rubygems
        DATA_DIRECTORY = Runtime.data_directory.join('rubygems').freeze
        ACTIVITY_URI = 'https://rubygems.org/api/v1/activity/just_updated.json'
        OPEN_TIMEOUT = 10
        READ_TIMEOUT = 60
        MAX_REDIRECTS = 5

        private_constant(*constants(false))

        def initialize(base_path: DATA_DIRECTORY, max_age_in_days: 1)
          @base_path = base_path
          @max_age_in_days = max_age_in_days
        end

        def fetch
          FileUtils.mkdir_p(base_path)

          gems = recently_published_gems
          if gems.empty?
            RuboCop::Nightly.logger.info 'No gems published in the requested window.'
            return []
          end

          gems.filter_map { download_and_extract_gem(it) }.uniq
        end

        private

        attr_reader :base_path, :max_age_in_days

        def recently_published_gems
          published_after = Date.today - max_age_in_days

          parse_json(get(URI(ACTIVITY_URI))).select do |gem|
            created_at = gem['version_created_at']
            next false if created_at.nil?

            Date.parse(created_at) > published_after
          rescue ArgumentError, TypeError
            false
          end
        end

        def parse_json(body)
          JSON.parse(body)
        rescue JSON::ParserError => e
          raise ExecutionError, "rubygems.org returned an unparseable response: #{e.message}"
        end

        # The activity feed lists one entry per (name, version, platform), so the platform has
        # to be part of both the download URL and the extraction path — otherwise every
        # platform variant collapses onto one directory and is silently skipped.
        def download_and_extract_gem(gem)
          name, version, platform = gem.values_at('name', 'number', 'platform')
          version ||= gem['version']
          return nil if name.nil? || version.nil?

          slug = [version, platform].compact.reject { it == 'ruby' }.join('-')
          extract_directory = File.join(base_path, name, slug)
          return extract_directory if Dir.exist?(extract_directory)

          fetch_gem(gem, name, slug, extract_directory)
        end

        def fetch_gem(gem, name, slug, extract_directory)
          uri = URI(gem['gem_uri'] || "https://rubygems.org/downloads/#{name}-#{slug}.gem")
          stage(uri, gem['sha'], "#{name}-#{slug}.gem", extract_directory)

          RuboCop::Nightly.logger.debug "Extracted #{name} (#{slug}) to #{extract_directory}"
          extract_directory
        rescue StandardError => e
          RuboCop::Nightly.logger.warn "Error processing gem #{name} (#{slug}): #{e.class}: #{e.message}"
          nil
        end

        # Everything happens in a staging directory and is moved into place only on success,
        # so a failed download or extraction cannot leave behind an empty directory that the
        # `Dir.exist?` guard would later treat as a completed download.
        def stage(uri, checksum, archive_name, extract_directory)
          Dir.mktmpdir('rubocop-nightly-gem') do |staging|
            archive = File.join(staging, archive_name)
            File.binwrite(archive, download(uri, checksum))

            contents = File.join(staging, 'contents')
            extract_gem(archive, contents)

            FileUtils.mkdir_p(File.dirname(extract_directory))
            FileUtils.mv(contents, extract_directory)
          end
        end

        def download(uri, expected_checksum)
          body = get(uri)
          verify_checksum(uri, body, expected_checksum)
          body
        end

        def verify_checksum(uri, body, expected_checksum)
          return if expected_checksum.nil? || expected_checksum.empty?

          actual = Digest::SHA256.hexdigest(body)
          return if actual == expected_checksum

          raise ExecutionError, "checksum mismatch for #{uri}: expected #{expected_checksum}, got #{actual}"
        end

        def get(uri, redirects_left: MAX_REDIRECTS)
          response = Net::HTTP.start(
            uri.host, uri.port,
            use_ssl: uri.scheme == 'https', open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT
          ) { it.request(Net::HTTP::Get.new(uri)) }

          case response
          when Net::HTTPSuccess then response.body
          when Net::HTTPRedirection then follow_redirect(uri, response, redirects_left)
          else raise ExecutionError, "GET #{uri} failed with #{response.code} #{response.message}"
          end
        end

        def follow_redirect(uri, response, redirects_left)
          raise ExecutionError, "too many redirects for #{uri}" if redirects_left.zero?

          get(URI.join(uri.to_s, response.fetch('location')), redirects_left: redirects_left - 1)
        end

        def extract_gem(archive, destination)
          FileUtils.mkdir_p(destination)
          Gem::Package.new(archive).extract_files(destination)
        end
      end
    end
  end
end
