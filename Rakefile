# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

require 'rubocop/rake_task'

RuboCop::RakeTask.new

task default: %i[spec rubocop]

namespace :gems do
  desc 'fetch latest rubocop gems from `config/gems.yml` sources'
  task :fetch do
    require 'yaml'
    require_relative 'lib/rubocop/nightly'

    gemfile_prefix = +<<~GEMFILE
      source 'https://rubygems.org'

      # gem 'racc'
    GEMFILE

    gems_config = YAML.safe_load_file('config/gems.yml')
    gems_config.each do |gem_config|
      gem_name = gem_config.fetch('name')
      gem_url = gem_config.fetch('url')
      gem_branch = gem_config.fetch('branch', 'master')

      gemfile_prefix << "gem '#{gem_name}', git: '#{gem_url}', branch: '#{gem_branch}'" << "\n"
    end

    FileUtils.mkdir_p(RuboCop::Nightly::Runtime.gems_data_directory)

    Dir.chdir(RuboCop::Nightly::Runtime.gems_data_directory) do
      Bundler.with_unbundled_env do
        # original_bundler_gemfile = ENV.fetch('BUNDLE_GEMFILE', nil)
        # ENV.delete('BUNDLE_GEMFILE')
        # ENV['BUNDLE_GEMFILE'] = RuboCop::Nightly::Runtime.gems_data_directory.join('Gemfile').to_s

        FileUtils.rm_f('Gemfile.lock')
        File.write('Gemfile', gemfile_prefix)

        system('bundle', 'config', 'set', '--local', 'path', Dir.pwd)
        system('bundle', 'install', '--redownload')
      end
    end
  end
end

namespace :cops do
  desc 'list cop dependencies'
  task :dependencies do
    require_relative 'lib/rubocop/nightly'

    RuboCop::Nightly::Configuration.build.dependencies.each do |cop_name, dependencies|
      puts "#{cop_name}: #{dependencies.join(',')}"
    end
  end
end
