# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Configuration do
  def build(raw, **) = described_class.build(raw, **)

  let(:raw) do
    {
      'Lint/Syntax' => { 'Enabled' => true },
      'Metrics/AbcSize' => { 'Enabled' => true, 'Max' => 17 },
      'Style/StringLiterals' => {
        'Enabled' => true,
        'EnforcedStyle' => 'single_quotes',
        'SupportedStyles' => %w[single_quotes double_quotes]
      },
      'Layout/HashAlignment' => {
        'Enabled' => true,
        'EnforcedHashRocketStyle' => 'key',
        'SupportedHashRocketStyles' => %w[key separator table]
      },
      'Layout/EndAlignment' => {
        'Enabled' => true,
        'EnforcedStyleAlignWith' => 'keyword',
        'SupportedStylesAlignWith' => %w[keyword variable start_of_line]
      }
    }
  end

  describe '.build' do
    it 'does not mutate the hash it was given' do
      expect { build(raw) }.not_to(change { Marshal.dump(raw) })
    end

    describe 'AllCops' do
      subject(:all_cops) { YAML.safe_load(build(raw).to_yaml).fetch('AllCops') }

      it 'pins the target ruby version' do
        expect(all_cops['TargetRubyVersion']).to eq(RuboCop::Nightly::Runtime.target_ruby_version)
      end

      it 'never exceeds what the driven RuboCop understands' do
        allow(RuboCop::Nightly::Runtime).to receive(:probe_target_ruby_versions).and_return([2.7, 3.0, 3.5])

        expect(RuboCop::Nightly::Runtime.target_ruby_version(bundle_gemfile: Pathname('/probe-a'))).to eq(3.5)
      end

      it 'falls back to the interpreter version when the probe fails' do
        allow(RuboCop::Nightly::Runtime).to receive(:probe_target_ruby_versions).and_return([])
        current = RUBY_VERSION.split('.').first(2).join('.').to_f

        expect(RuboCop::Nightly::Runtime.target_ruby_version(bundle_gemfile: Pathname('/probe-b'))).to eq(current)
      end

      it 'enables new cops' do
        expect(all_cops['NewCops']).to eq('enable')
      end

      it 'omits ParserEngine unless asked' do
        expect(all_cops).not_to have_key('ParserEngine')
      end

      it 'sets ParserEngine when asked' do
        engine = YAML.safe_load(build(raw, parser_engine: 'parser_prism').to_yaml).dig('AllCops', 'ParserEngine')

        expect(engine).to eq('parser_prism')
      end
    end

    describe 'non-Hash values' do
      it 'survives the plugins array injected alongside cop entries' do
        expect { build(raw).to_yaml }.not_to raise_error
      end

      it 'does not mutate the frozen plugin name list', :aggregate_failures do
        expect { build(raw) }.not_to raise_error
        expect(RuboCop::Nightly::Runtime::PluginRegistry.all_names).to all(be_frozen)
      end

      it 'tolerates a string-valued top-level key' do
        expect { build(raw.merge('require' => 'something')) }.not_to raise_error
      end
    end

    describe 'keep_core_departments' do
      subject(:kept) { YAML.safe_load(build(raw, keep_core_departments: true, remove_plugins: true).to_yaml).keys }

      it 'keeps Layout, which the Layour typo used to drop' do
        expect(kept).to include('Layout/HashAlignment')
      end

      it 'keeps AllCops' do
        expect(kept).to include('AllCops')
      end

      it 'keeps Gemspec' do
        with_gemspec = build(
          raw.merge('Gemspec/RequireMFA' => { 'Enabled' => true }),
          keep_core_departments: true, remove_plugins: true
        )

        expect(YAML.safe_load(with_gemspec.to_yaml).keys).to include('Gemspec/RequireMFA')
      end

      it 'drops plugin departments' do
        with_plugin = build(
          raw.merge('RSpec/DescribedClass' => { 'Enabled' => true }),
          keep_core_departments: true, remove_plugins: true
        )

        expect(YAML.safe_load(with_plugin.to_yaml).keys).not_to include('RSpec/DescribedClass')
      end
    end
  end

  describe 'building from the rubocop executable' do
    def stub_show_cops(stdout, exitstatus: 0, stderr: '')
      status = instance_double(Process::Status, success?: exitstatus.zero?, exitstatus: exitstatus)
      allow(RuboCop::Nightly::Runtime).to receive(:execute).and_return([stdout, stderr, status])
    end

    it 'raises when the executable fails' do
      stub_show_cops('', exitstatus: 1, stderr: 'cannot load such file')

      expect { described_class.build }
        .to raise_error(RuboCop::Nightly::ExecutionError, /cannot load such file/)
    end

    it 'raises when the dump is empty' do
      stub_show_cops('')

      expect { described_class.build }.to raise_error(RuboCop::Nightly::ExecutionError, /no parseable/)
    end

    it 'parses a dump into a configuration' do
      stub_show_cops("Style/Thing:\n  Enabled: false\n")

      expect(described_class.build.cop_names).to eq(['Style/Thing'])
    end

    it 'requires plugins unless they are being removed' do
      stub_show_cops("Style/Thing:\n  Enabled: true\n")

      described_class.build(remove_plugins: true)

      expect(RuboCop::Nightly::Runtime).to have_received(:execute)
        .with('--show-cops', '--force-default-config', require_plugins: false)
    end
  end

  describe '#cop_names' do
    it 'recognises consecutive capitals after the slash' do
      names = build(raw.merge('Gemspec/RequireMFA' => { 'Enabled' => true })).cop_names

      expect(names).to include('Gemspec/RequireMFA')
    end

    it 'recognises nested departments' do
      names = build(raw.merge('RSpec/Capybara/SpecificMatcher' => { 'Enabled' => true })).cop_names

      expect(names).to include('RSpec/Capybara/SpecificMatcher')
    end

    it 'excludes non-cop keys', :aggregate_failures do
      names = build(raw).cop_names

      expect(names).not_to include('AllCops')
      expect(names).not_to include('plugins')
    end
  end

  describe '#style_parameters' do
    subject(:parameters) { build(raw).style_parameters }

    it 'pairs SupportedStyles with EnforcedStyle' do
      expect(parameters.fetch('Style/StringLiterals')).to eq('SupportedStyles' => 'EnforcedStyle')
    end

    it 'pairs SupportedHashRocketStyles with EnforcedHashRocketStyle' do
      expect(parameters.fetch('Layout/HashAlignment'))
        .to eq('SupportedHashRocketStyles' => 'EnforcedHashRocketStyle')
    end

    it 'pairs SupportedStylesAlignWith with EnforcedStyleAlignWith' do
      expect(parameters.fetch('Layout/EndAlignment'))
        .to eq('SupportedStylesAlignWith' => 'EnforcedStyleAlignWith')
    end
  end

  describe 'plugins and departments' do
    it 'omits the plugins key when plugins are removed' do
      expect(YAML.safe_load(build(raw, remove_plugins: true).to_yaml)).not_to have_key('plugins')
    end

    it 'drops a require key when plugins are removed' do
      configuration = build(raw.merge('require' => ['x']), remove_plugins: true)

      expect(YAML.safe_load(configuration.to_yaml)).not_to have_key('require')
    end

    it 'force-enables every cop when asked' do
      disabled = raw.merge('Style/Disabled' => { 'Enabled' => false })
      enabled = YAML.safe_load(build(disabled, enable_all_cops: true).to_yaml)

      expect(enabled.dig('Style/Disabled', 'Enabled')).to be(true)
    end

    it 'strips Include and Exclude from cop entries' do
      configuration = build(raw.merge('Style/Thing' => { 'Enabled' => true, 'Include' => ['a'], 'Exclude' => ['b'] }))
      entry = YAML.safe_load(configuration.to_yaml).fetch('Style/Thing')

      expect(entry.keys).not_to include('Include', 'Exclude')
    end

    it 'keeps an AllCops section supplied by the caller' do
      configuration = build(raw.merge('AllCops' => { 'Exclude' => ['vendor/**/*'] }))

      expect(YAML.safe_load(configuration.to_yaml).dig('AllCops', 'Exclude')).to eq(['vendor/**/*'])
    end

    it 'tolerates a non-Hash AllCops' do
      expect { build(raw.merge('AllCops' => 'nonsense')) }.not_to raise_error
    end
  end

  describe '#style_parameters with no Enforced partner' do
    it 'ignores a Supported key that names no style axis' do
      configuration = build(raw.merge('Style/Yoda' => { 'Enabled' => true, 'SupportedOperators' => %w[< >] }))

      expect(configuration.style_parameters.fetch('Style/Yoda')).to be_empty
    end

    it 'assumes EnforcedStyle for a bare SupportedStyles' do
      configuration = build(raw.merge('Style/Bare' => { 'Enabled' => true, 'SupportedStyles' => %w[a b] }))

      expect(configuration.style_parameters.fetch('Style/Bare')).to eq('SupportedStyles' => 'EnforcedStyle')
    end

    it 'returns no parameters for a non-Hash cop entry' do
      configuration = build(raw.merge('Style/Weird' => 'nonsense'))

      expect(configuration.style_parameters.fetch('Style/Weird')).to eq({})
    end
  end

  describe 'configuration values the corpus cannot satisfy' do
    let(:inflector_cop) do
      {
        'RSpec/SpecFilePathFormat' => {
          'Enabled' => true,
          'EnforcedInflector' => 'default',
          'SupportedInflectors' => %w[default active_support],
          'InflectorPath' => './config/initializers/inflections.rb'
        }
      }
    end

    # `active_support` makes the cop load `InflectorPath`, which no checkout provides, so every
    # variant picking it raises and is reported exactly like a real cop crash.
    it 'never selects the active_support inflector' do
      configuration = build(raw.merge(inflector_cop))
      chosen = configuration.variants.map { it.dig('RSpec/SpecFilePathFormat', 'EnforcedInflector') }

      expect(chosen.uniq).to eq(['default'])
    end

    it 'still runs the cop under the inflector it can satisfy' do
      configuration = build(raw.merge(inflector_cop))
      enabled = configuration.variants.select { it.dig('RSpec/SpecFilePathFormat', 'Enabled') }

      expect(enabled).not_to be_empty
    end

    it 'leaves other cops fully varied' do
      configuration = build(raw.merge(inflector_cop))
      styles = configuration.variants.map { it.dig('Style/StringLiterals', 'EnforcedStyle') }

      expect(styles.uniq).to match_array(%w[single_quotes double_quotes])
    end
  end

  describe '#variants' do
    subject(:variants) { build(raw).variants }

    it 'enables a cop that has no configurable styles' do
      expect(variants.count { it.dig('Metrics/AbcSize', 'Enabled') }).to be >= 1
    end

    it 'always keeps Lint/Syntax enabled' do
      expect(variants).to all(include('Lint/Syntax' => hash_including('Enabled' => true)))
    end

    it 'enables every cop in at least one variant' do
      never_enabled = build(raw).cop_names.reject do |cop_name|
        variants.any? { it.dig(cop_name, 'Enabled') }
      end

      expect(never_enabled).to be_empty
    end

    it 'covers every supported style of every cop' do
      configuration = build(raw)

      configuration.style_parameters.each do |cop_name, pairs|
        pairs.each do |supported_key, enforced_key|
          expect(variants.filter_map { it.dig(cop_name, enforced_key) }.uniq)
            .to match_array(raw.fetch(cop_name).fetch(supported_key))
        end
      end
    end

    it 'writes styles to the paired Enforced key, not always EnforcedStyle' do
      expect(variants.filter_map { it.dig('Layout/EndAlignment', 'EnforcedStyleAlignWith') })
        .to include('variable')
    end

    it 'returns plain hashes rather than pairs' do
      expect(variants).to all(be_a(Hash))
    end

    it 'does not share mutable state between variants' do
      variants.first['Metrics/AbcSize']['Max'] = 999

      expect(variants.last.dig('Metrics/AbcSize', 'Max')).to eq(17)
    end
  end
end
