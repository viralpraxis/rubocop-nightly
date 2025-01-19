# frozen_string_literal: true

require 'logger'

require_relative 'nightly/version'

require_relative 'nightly/cli'
require_relative 'nightly/cli/parser'

require_relative 'nightly/runtime'
require_relative 'nightly/runtime/plugin_registry'
require_relative 'nightly/executor'
require_relative 'nightly/runner'
require_relative 'nightly/configuration'
require_relative 'nightly/configuration/dependencies_miner'
require_relative 'nightly/null_formatter'

require_relative 'nightly/source/rubygems'
require_relative 'nightly/source/mirror'
require_relative 'nightly/source/git'
require_relative 'nightly/source'

module RuboCop
  module Nightly
    def self.logger
      @logger ||= Logger.new($stdout) # rubocop:disable ThreadSafety/ClassInstanceVariable
                        .tap { it.progname = 'rubocop-nightly' }
                        .tap { it.formatter = proc { |severity, _time, _progname, msg| "[#{severity}]: #{msg}\n" } }
    end
  end
end
