# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

require 'rubocop/rake_task'

RuboCop::RakeTask.new

task default: %i[spec rubocop]

namespace :gems do
  desc 'install latest rubocop gems from `config/gems.yml` sources'
  task :install do
    require 'yaml'
    require 'fileutils'
    require_relative 'lib/rubocop/nightly'

    gems_config = YAML.safe_load_file(File.join(__dir__, 'config', 'gems.yml'))
    data_directory = RuboCop::Nightly::Runtime.gems_data_directory

    FileUtils.mkdir_p(data_directory)

    Dir.chdir(data_directory) do
      Bundler.with_unbundled_env do
        FileUtils.rm_f('Gemfile.lock')
        File.write('Gemfile', GemfileBuilder.call(gems_config))

        sh('bundle', 'config', 'set', '--local', 'path', Dir.pwd)
        sh('bundle', 'install')

        run_post_install_scripts(gems_config)
      end
    end
  end
end

# Runs through a shell by design (the scripts use `$(...)`), so these values are trusted
# config, not user input. `sh` aborts the task if one of them fails.
def run_post_install_scripts(gems_config)
  gems_config.each do |gem_config|
    script = gem_config['post_install_script']
    next if script.nil? || script.empty?

    sh(script)
  end
end

namespace :cops do
  desc 'list cop dependencies'
  task :dependencies do
    require_relative 'lib/rubocop/nightly'

    Dir.chdir(RuboCop::Nightly::Runtime.gems_data_directory) do
      RuboCop::Nightly::Configuration.build.dependencies.each do |cop_name, dependencies|
        puts "#{cop_name}: #{dependencies.to_a.join(',')}"
      end
    end
  end
end

# Builds the Gemfile installed into the data directory. Values are quoted so that a name or
# URL containing a quote cannot break out into arbitrary Ruby.
module GemfileBuilder
  module_function

  def call(gems_config)
    lines = ['# frozen_string_literal: true', '', "source 'https://rubygems.org'", '']

    gems_config.each { lines << declaration_for(it) }

    lines << 'gem "pry"' << ''
    lines.join("\n")
  end

  def declaration_for(gem_config)
    name = gem_config.fetch('name')
    url = gem_config['url']
    branch = gem_config.fetch('branch', 'master')

    declaration = "gem #{name.dump}"
    declaration << ", git: #{url.dump}, branch: #{branch.dump}" if url
    declaration
  end
end
