# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

require 'rubocop/rake_task'

RuboCop::RakeTask.new

task default: %i[spec rubocop]

namespace :gems do # rubocop:disable Metrics/BlockLength
  desc 'fetch latest rubocop gems from `config/gems.yml` sources'
  task :fetch do
    require 'yaml'
    require_relative 'lib/rubocop/nightly'

    gemfile_content = +<<~GEMFILE
      # frozen_string_literal: true

      source 'https://rubygems.org'

    GEMFILE

    gems_config = YAML.safe_load_file('config/gems.yml')
    gems_config.each do |gem_config|
      gem_name = gem_config.fetch('name')
      gem_url = gem_config.fetch('url', nil)
      gem_branch = gem_config.fetch('branch', 'master')

      gemfile_content << "gem '#{gem_name}'"
      gemfile_content << ", git: '#{gem_url}', branch: '#{gem_branch}'" if gem_url
      gemfile_content << "\n"
    end
    gemfile_content << "gem 'pry'" << "\n"

    FileUtils.mkdir_p(RuboCop::Nightly::Runtime.gems_data_directory)

    Dir.chdir(RuboCop::Nightly::Runtime.gems_data_directory) do
      Bundler.with_unbundled_env do
        FileUtils.rm_f('Gemfile.lock')
        File.write('Gemfile', gemfile_content)

        system('bundle', 'config', 'set', '--local', 'path', Dir.pwd)
        system('bundle', 'install', '--redownload')

        gems_config.select { it.key?('post_install_script') }.each { system(it.fetch('post_install_script')) }
      end
    end
  end
end

namespace :cops do
  desc 'list cop dependencies'
  task :dependencies do
    require_relative 'lib/rubocop/nightly'

    Dir.chdir(RuboCop::Nightly::Runtime.gems_data_directory) do
      RuboCop::Nightly::Configuration.build.dependencies.each do |cop_name, dependencies|
        puts "#{cop_name}: #{dependencies.join(',')}"
      end
    end
  end
end
