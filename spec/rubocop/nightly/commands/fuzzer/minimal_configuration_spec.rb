# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Commands::Fuzzer::MinimalConfiguration do
  subject(:projected) { described_class.call(variant, 'Style/Thing') }

  let(:variant) do
    {
      'AllCops' => { 'TargetRubyVersion' => 4.0, 'ParserEngine' => 'parser_prism', 'NewCops' => 'enable' },
      'Style/Thing' => {
        'Enabled' => true, 'EnforcedStyle' => 'inline', 'Max' => 10,
        'Description' => 'x', 'VersionAdded' => '0.1', 'SupportedStyles' => %w[inline group]
      },
      'Style/Other' => { 'Enabled' => true }
    }
  end

  it 'disables everything by default' do
    expect(projected.fetch('AllCops')).to include('DisabledByDefault' => true)
  end

  it 'carries over TargetRubyVersion and ParserEngine', :aggregate_failures do
    expect(projected.fetch('AllCops')).to include('TargetRubyVersion' => 4.0)
    expect(projected.fetch('AllCops')).to include('ParserEngine' => 'parser_prism')
  end

  it 'keeps the Enforced keys the variant chose' do
    expect(projected.fetch('Style/Thing')).to include('EnforcedStyle' => 'inline')
  end

  it 'keeps other behavioural settings' do
    expect(projected.fetch('Style/Thing')).to include('Max' => 10)
  end

  it 'drops documentation and metadata', :aggregate_failures do
    expect(projected.fetch('Style/Thing')).not_to have_key('Description')
    expect(projected.fetch('Style/Thing')).not_to have_key('VersionAdded')
  end

  it 'drops the Supported* lists' do
    expect(projected.fetch('Style/Thing')).not_to have_key('SupportedStyles')
  end

  it 'drops unrelated cops' do
    expect(projected).not_to have_key('Style/Other')
  end

  it 'enables the cop even if the variant had it disabled' do
    variant['Style/Thing']['Enabled'] = false

    expect(projected.fetch('Style/Thing')).to include('Enabled' => true)
  end

  it 'tolerates a cop absent from the variant' do
    expect(described_class.call({}, 'Style/Missing').fetch('Style/Missing')).to eq('Enabled' => true)
  end

  describe 'plugin selection' do
    let(:plugins) { %w[rubocop-rspec rubocop-rails rubocop-graphql] }

    def config(cop, variant_extras = {})
      described_class.new({ 'plugins' => plugins, 'AllCops' => {}, cop => { 'Enabled' => true } }
                           .merge(variant_extras), cop).to_h
    end

    it 'names no plugin for a core cop' do
      expect(config('Style/Thing')).not_to have_key('plugins')
    end

    it 'names only the plugin that owns the cop' do
      expect(config('RSpec/Thing')['plugins']).to eq(['rubocop-rspec'])
    end

    it 'matches a department whose gem name uses underscores' do
      expect(config('GraphQL/Thing')['plugins']).to eq(['rubocop-graphql'])
    end

    it 'falls back to every plugin when the owner cannot be identified' do
      expect(config('Unknown/Thing')['plugins']).to eq(plugins)
    end

    it 'omits the key when the variant declares no plugins' do
      expect(described_class.new({ 'AllCops' => {}, 'RSpec/Thing' => {} }, 'RSpec/Thing').to_h)
        .not_to have_key('plugins')
    end

    it 'tolerates a non-Hash cop entry' do
      expect(described_class.new({ 'Style/Thing' => 'nonsense' }, 'Style/Thing').to_h['Style/Thing'])
        .to eq('Enabled' => true)
    end
  end
end
