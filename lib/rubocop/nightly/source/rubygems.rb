# frozen_string_literal: true

require 'net/http'
require 'json'
require 'fileutils'
require 'date'
require 'rubygems/package'

module RuboCop
  module Nightly
    module Source
      class Rubygems
        DATA_DIRECTORY = Runtime.data_directory.join('rubygems').freeze
        private_constant(*constants(false))

        def initialize(base_path: DATA_DIRECTORY)
          @base_path = base_path
        end

        def fetch
          FileUtils.mkdir_p(@base_path)

          if (gems = fetch_todays_gems).empty?
            puts 'No gems published today.'
            return
          end

          gems.filter_map do |gem|
            gem_name, version = gem.values_at('name', 'version')
            puts "Processing gem: #{gem_name} (version: #{version})"

            download_and_extract_gem(gem_name, version, @base_path)
          end
        end

        def fetch_todays_gems
          response = Net::HTTP.get(URI('https://rubygems.org/api/v1/activity/just_updated.json'))
          gems = JSON.parse(response)

          today = Date.today - 100
          gems.select do |gem|
            gem_date = Date.parse(gem['version_created_at'])
            gem_date > today
          end
        end

        def download_and_extract_gem(gem_name, version, destination) # rubocop:disable Metrics/MethodLength
          gem_url = "https://rubygems.org/downloads/#{gem_name}-#{version}.gem"
          gem_file = File.join(destination, "#{gem_name}-#{version}.gem")

          gem_extract_dir = File.join(destination, gem_name, version)
          return gem_extract_dir if Dir.exist?(gem_extract_dir)

          begin
            download_file(gem_url, gem_file)
            extract_gem(gem_file, gem_extract_dir)
            File.delete(gem_file)

            puts "Gem #{gem_name} (version: #{version}) downloaded and extracted to #{gem_extract_dir}"

            gem_extract_dir
          rescue StandardError => e
            puts "Error processing gem #{gem_name} (version: #{version}): #{e.message}"

            nil
          end
        end

        def download_file(url, destination)
          response = Net::HTTP.get_response(URI(url))
          raise "Failed to download #{url}" unless response.is_a?(Net::HTTPSuccess)

          File.binwrite(destination, response.body)
        end

        def extract_gem(gem_file, destination)
          FileUtils.mkdir_p(destination)
          Gem::Package.new(gem_file).extract_files(destination)
        end
      end
    end
  end
end
