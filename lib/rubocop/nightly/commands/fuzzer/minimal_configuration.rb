# frozen_string_literal: true

require 'yaml'

module RuboCop
  module Nightly
    module Commands
      module Fuzzer
        # Projects the ~240 KB variant that triggered a crash down to the handful of lines that
        # actually matter: every cop off by default, the offending cop on, and the style keys the
        # variant had chosen for it.
        class MinimalConfiguration
          # Carried over because a crash can be specific to the parser or the target version;
          # dropping them would produce an MRE that does not reproduce.
          ALL_COPS_KEYS = %w[TargetRubyVersion ParserEngine].freeze

          METADATA = /\A(?:Description|StyleGuide|Reference|Version|Safe|AutoCorrect|Include|Exclude|Supported)/

          private_constant :ALL_COPS_KEYS, :METADATA

          def self.call(...) = new(...).to_h

          def initialize(variant, cop_name)
            @variant = variant
            @cop_name = cop_name
          end

          def to_h
            { 'AllCops' => all_cops }.merge(plugins).merge(cop_name => cop_settings)
          end

          def to_yaml = YAML.dump(to_h)

          private

          attr_reader :variant, :cop_name

          def all_cops
            inherited = (variant['AllCops'] || {}).slice(*ALL_COPS_KEYS)

            { 'DisabledByDefault' => true, 'SuggestExtensions' => false }.merge(inherited)
          end

          # A plugin cop is unknown to a bare `rubocop`, which rejects the example outright with
          # "unrecognized cop or department". Only the plugin that owns the cop is named: the
          # whole list would make the example unrunnable anywhere the other plugins are not
          # installed, which is precisely where these examples get taken.
          def plugins
            declared = variant['plugins']
            return {} unless declared.is_a?(Array) && !declared.empty?
            return {} if RuboCop::Nightly::Runtime::CORE_DEPARTMENTS.include?(department)

            owner = owning_plugin(declared)

            { 'plugins' => owner ? [owner] : declared }
          end

          def department = cop_name.split('/').first

          # Compares department and gem name with case and underscores removed, which is enough
          # for every RuboCop naming style: `RSpecRails`/`rubocop-rspec_rails`,
          # `GraphQL`/`rubocop-graphql`, `FactoryBot`/`rubocop-factory_bot`. Falls back to the
          # full list rather than guessing wrong and emitting an example that cannot run.
          def owning_plugin(declared)
            target = normalize(department)

            declared.find { normalize(it.delete_prefix('rubocop-')) == target }
          end

          def normalize(value) = value.downcase.delete('_')

          # Everything except documentation and metadata. An allowlist of `Enabled` + `Enforced*`
          # looks tidier but drops load-bearing settings — `RSpec/SpecFilePathFormat` needs its
          # `InflectorPath`, and without it the example silently stops reproducing. `Supported*`
          # lists are dropped because the paired `Enforced*` value already pins the choice.
          def cop_settings
            settings = variant[cop_name]
            return { 'Enabled' => true } unless settings.is_a?(Hash)

            settings.reject { |key, _| METADATA.match?(key) }.merge('Enabled' => true)
          end
        end
      end
    end
  end
end
