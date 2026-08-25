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

  config.before(:suite) do
    system('bundle', 'exec', 'rake', 'gems:install', exception: true) if ENV.key?('CI')
  end

  config.before(:suite) { RuboCop::Nightly.logger.reopen(File::NULL) }

  config.before do
    RuboCop::Nightly.logger.level = Logger::Severity::FATAL
  end
end
