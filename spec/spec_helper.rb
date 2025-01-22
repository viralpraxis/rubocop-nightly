# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  enable_coverage :branch
end

require 'rubocop/nightly'

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'

  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  if ENV.key?('CI')
    config.before(:all) do
      `bundle exec rake gems:fetch`
    end
  end

  config.before(:all) do
    RuboCop::Nightly.logger.level = Logger::Severity::FATAL
  end
end

Dir["#{__dir__}/support/**/*.rb"].each { require_relative(it) }
