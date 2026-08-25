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
end
