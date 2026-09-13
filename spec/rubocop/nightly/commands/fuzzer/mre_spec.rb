# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Commands::Fuzzer::Mre do
  let(:directory) { Pathname('/data/reproductions/variant-0-abcd1234') }
  let(:script) { directory.join('mre', 'Style-Thing-deadbeef', 'mre.sh') }

  describe '.written' do
    it 'names the script relative to the reproduction directory the log line already carries' do
      expect(described_class.written(script, directory).to_s).to eq('mre/Style-Thing-deadbeef/mre.sh')
    end

    it 'appends the detail when there is one' do
      expect(described_class.written(script, directory, 'whole file').to_s)
        .to eq('mre/Style-Thing-deadbeef/mre.sh (whole file)')
    end
  end

  describe '.failed' do
    it 'reads as a reason rather than a location' do
      expect(described_class.failed('no source file').to_s).to eq('no MRE: no source file')
    end
  end

  it 'never spans more than one line, whatever it is carrying', :aggregate_failures do
    [described_class.written(script, directory, 'whole file'), described_class.failed('boom')].each do |mre|
      expect(mre.to_s).not_to include("\n")
    end
  end
end
