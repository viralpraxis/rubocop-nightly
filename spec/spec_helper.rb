# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  enable_coverage :branch

  add_filter '/spec/'
end

require 'rubocop/nightly'

Dir["#{__dir__}/support/**/*.rb"].each { require_relative(it) }

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'

  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # `before(:all)` runs once per top-level group; this must happen exactly once per run.
  # `gems:install` is the task that fetches RuboCop core/plugins — `install` is
  # bundler/gem_tasks' build-and-install-the-gem task, which is not what is wanted here.
  config.before(:suite) do
    system('bundle', 'exec', 'rake', 'gems:install', exception: true) if ENV.key?('CI')
  end

  config.before do
    RuboCop::Nightly.logger.level = Logger::Severity::FATAL
  end
end
