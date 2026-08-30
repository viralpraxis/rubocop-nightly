# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Commands::Fuzzer::BrokenCorrectionReport do
  let(:data_home) { Dir.mktmpdir('rubocop-nightly-broken') }
  let(:directory) { Pathname(data_home).join('report') }
  let(:target) { File.join(data_home, 'thing.rb') }
  let(:corrected_path) { File.join(data_home, 'corrected-source.rb') }
  let(:finding) do
    RuboCop::Nightly::Commands::Fuzzer::Findings::BrokenCorrection.new(
      path: target, diagnostic: "unexpected 'end', ignoring it"
    )
  end

  before do
    FileUtils.mkdir_p(directory)
    File.write(target, "class Foo\nend\n")
    File.write(corrected_path, "class Foo = 1\n")
    allow(RuboCop::Nightly.logger).to receive(:info)
    allow(RuboCop::Nightly.logger).to receive(:warn)
  end

  after { FileUtils.remove_entry(data_home) }

  describe '.write' do
    let(:finding) do
      RuboCop::Nightly::Commands::Fuzzer::Findings::BrokenCorrection.new(
        path: target, diagnostic: "unexpected 'end', ignoring it"
      )
    end
    let(:corrected_path) { File.join(data_home, 'corrected-source.rb') }

    before { File.write(corrected_path, "class Foo = 1\n") }

    it 'copies out the corrected source, which the workspace would otherwise destroy' do
      described_class.write(finding, corrected_path, directory)

      expect(Pathname.glob(directory.join('mre/*/corrected.rb')).first.read).to eq("class Foo = 1\n")
    end

    it 'writes a runnable script naming the diagnostic and the variant configuration' do
      described_class.write(finding, corrected_path, directory)
      script = Pathname.glob(directory.join('mre/*/mre.sh')).first

      expect(script.read).to include("unexpected 'end'").and include(directory.join('configuration.yml').to_s)
    end

    it 'keeps findings for different files apart' do
      other = RuboCop::Nightly::Commands::Fuzzer::Findings::BrokenCorrection.new(
        path: File.join(data_home, 'other.rb'), diagnostic: 'boom'
      )

      described_class.write(finding, corrected_path, directory)
      described_class.write(other, corrected_path, directory)

      expect(Pathname.glob(directory.join('mre/*')).size).to eq(2)
    end

    it 'warns rather than raising when the corrected source is gone' do
      described_class.write(finding, File.join(data_home, 'missing.rb'), directory)

      expect(RuboCop::Nightly.logger).to have_received(:warn).with(/Could not write MRE/)
    end
  end
end
