# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Commands::Fuzzer::Reproduction do
  let(:data_home) { Dir.mktmpdir('rubocop-nightly-repro') }
  let(:directory) { Pathname(data_home).join('report') }
  let(:variant) { { 'AllCops' => { 'TargetRubyVersion' => 3.4 }, 'Style/Thing' => { 'Enabled' => true } } }
  let(:crash) do
    RuboCop::Nightly::Commands::Fuzzer::ErrorDetails.new(cop_name: 'Style/Thing', source_pointer: "#{target}:2:1")
  end
  let(:target) { File.join(data_home, 'thing.rb') }

  before do
    FileUtils.mkdir_p(directory)
    File.write(target, "class Foo\n  BAR = 1\nend\n")
    allow(RuboCop::Nightly.logger).to receive(:info)
    allow(RuboCop::Nightly.logger).to receive(:warn)
  end

  after { FileUtils.remove_entry(data_home) }

  def written = Pathname.glob(directory.join('mre/*/*')).map { it.basename.to_s }.sort

  describe '.write_mre' do
    it 'writes a whole-file example when reduction is off' do
      described_class.write_mre(crash, variant, directory)

      expect(written).to eq(%w[mre.sh mre.yml])
    end

    it 'names the directory after the cop and the crash location' do
      described_class.write_mre(crash, variant, directory)

      expect(Pathname.glob(directory.join('mre/*')).map { it.basename.to_s })
        .to all(match(/\AStyle-Thing-[0-9a-f]{8}\z/))
    end

    it 'keeps separate crashes in separate directories' do
      other = RuboCop::Nightly::Commands::Fuzzer::ErrorDetails.new(
        cop_name: 'Style/Thing', source_pointer: "#{target}:9:1"
      )

      described_class.write_mre(crash, variant, directory)
      described_class.write_mre(other, variant, directory)

      expect(Pathname.glob(directory.join('mre/*')).size).to eq(2)
    end

    it 'produces a runnable script referencing the offending file' do
      described_class.write_mre(crash, variant, directory)
      script = Pathname.glob(directory.join('mre/*/mre.sh')).first

      expect(script.read).to include('--only Style/Thing').and include(target)
    end

    it 'warns and writes nothing when the source file is gone' do
      FileUtils.rm_f(target)

      described_class.write_mre(crash, variant, directory)

      expect(RuboCop::Nightly.logger).to have_received(:warn).with(/No source file/)
    end

    it 'falls back to the whole file when reduction yields nothing' do
      allow(RuboCop::Nightly::Commands::Fuzzer::Reduction).to receive(:call).and_return(nil)

      described_class.write_mre(crash, variant, directory, reduce: true)

      expect(written).to eq(%w[mre.sh mre.yml])
    end

    it 'falls back to the whole file when reduction raises' do
      allow(RuboCop::Nightly::Commands::Fuzzer::Reduction).to receive(:call).and_raise(StandardError, 'boom')

      described_class.write_mre(crash, variant, directory, reduce: true)

      expect(RuboCop::Nightly.logger).to have_received(:warn).with(/Reduction failed/)
    end

    it 'writes the reduced example when reduction succeeds' do
      result = instance_double(
        RuboCop::Nightly::Commands::Fuzzer::Reduction::Result,
        source: "class Foo\nend\n", configuration: { 'Style/Thing' => {} }, command: "echo hi\n",
        signature: instance_double(RuboCop::Nightly::Commands::Fuzzer::Signature, describe: 'Style/Thing (X)'),
        original_size: 3, budget: 'budget'
      )
      allow(RuboCop::Nightly::Commands::Fuzzer::Reduction).to receive(:call).and_return(result)

      described_class.write_mre(crash, variant, directory, reduce: true)

      expect(written).to eq(%w[mre.rb mre.sh mre.yml])
    end
  end
end
