# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'logger'
require 'tempfile'
require 'uri'
require 'yaml'

require_relative 'nightly/version'
require_relative 'nightly/errors'

require_relative 'nightly/runner/base'

require_relative 'nightly/runtime'
require_relative 'nightly/runtime/plugin_registry'

require_relative 'nightly/cli'
require_relative 'nightly/cli/parser'

require_relative 'nightly/corpus'
require_relative 'nightly/executor'
require_relative 'nightly/configuration'
require_relative 'nightly/configuration/builder'
require_relative 'nightly/configuration/dependencies_miner'
require_relative 'nightly/configuration/traversal'
require_relative 'nightly/configuration/covering_array'

require_relative 'nightly/source/http'
require_relative 'nightly/source/rubygems'
require_relative 'nightly/source/mirror'
require_relative 'nightly/source/git'
require_relative 'nightly/source'

require_relative 'nightly/commands/compare'
require_relative 'nightly/commands/compare/revision_specification'
require_relative 'nightly/commands/compare/report'
require_relative 'nightly/commands/compare/runner'

require_relative 'nightly/commands/fuzzer/error_details'
require_relative 'nightly/commands/fuzzer/findings'
require_relative 'nightly/commands/fuzzer/diagnostics'
require_relative 'nightly/commands/fuzzer/broken_correction_report'
require_relative 'nightly/commands/fuzzer/reporter'
require_relative 'nightly/commands/fuzzer/workspace'
require_relative 'nightly/commands/fuzzer/correction_check'
require_relative 'nightly/commands/fuzzer/budget'
require_relative 'nightly/commands/fuzzer/signature'
require_relative 'nightly/commands/fuzzer/minimal_configuration'
require_relative 'nightly/commands/fuzzer/oracle'
require_relative 'nightly/commands/fuzzer/reducer'
require_relative 'nightly/commands/fuzzer/reduction'
require_relative 'nightly/commands/fuzzer/reproduction'
require_relative 'nightly/commands/fuzzer/runner'

module RuboCop
  module Nightly
    class << self
      def logger
        @logger ||= Logger.new($stderr) # rubocop:disable ThreadSafety/ClassInstanceVariable
                          .tap { it.progname = 'rubocop-nightly' }
                          .tap { it.formatter = proc { |severity, _time, _progname, msg| "[#{severity}]: #{msg}\n" } }
      end
    end
  end
end
