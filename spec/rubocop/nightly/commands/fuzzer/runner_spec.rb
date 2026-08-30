# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Commands::Fuzzer::Runner do
  subject(:runner) { described_class.new(['/a.rb'], configuration: configuration) }

  let(:data_home) { Dir.mktmpdir('rubocop-nightly-spec') }
  let(:clean_run) { ['', '', instance_double(Process::Status, success?: true, exitstatus: 0)] }

  around do |example|
    with_environment_variable('XDG_DATA_HOME', data_home) do
      FileUtils.mkdir_p(RuboCop::Nightly::Runtime.gems_data_directory)
      example.run
    end
  ensure
    FileUtils.remove_entry(data_home)
  end

  before { allow(RuboCop::Nightly::Runtime).to receive(:execute).and_return(clean_run) }

  def reproduction_directories
    Pathname.glob(RuboCop::Nightly::Runtime.data_directory.join('fuzzer/reproductions/*')).sort
  end

  def executed_arguments
    expect(RuboCop::Nightly::Runtime).to have_received(:execute) do |*arguments, **|
      return arguments
    end
  end

  describe '#run' do
    context 'when configuration does not have supported styles' do
      let(:configuration) do
        RuboCop::Nightly::Configuration.build(
          {
            'Department/CopName1' => { 'Enabled' => true },
            'Department/CopName2' => { 'Enabled' => true }
          }
        )
      end

      it 'invokes rubocop once' do
        runner.run

        expect(RuboCop::Nightly::Runtime).to have_received(:execute).once
      end

      it 'passes the expected arguments' do
        runner.run

        expect(RuboCop::Nightly::Runtime).to have_received(:execute).with(
          '-c', a_string_ending_with('configuration.yml'),
          '--format', 'RuboCop::Nightly::NullFormatter',
          '--parallel',
          '-r', File.expand_path('../../../../../lib/rubocop/nightly/null_formatter.rb', __dir__),
          '/a.rb',
          require_plugins: true, timeout: nil, warnings: true
        )
      end

      it 'enables cops that have no configurable styles' do
        expect(configuration.variants.first.dig('Department/CopName1', 'Enabled')).to be(true)
      end
    end

    context 'when configuration does have supported styles' do
      let(:configuration) do
        RuboCop::Nightly::Configuration.build(
          {
            'Department/CopName1' => {
              'Enabled' => true,
              'SupportedStyles' => %w[style-a-1 style-a-2 style-a-3]
            },
            'Department/CopName2' => {
              'Enabled' => true,
              'SupportedStyles' => %w[style-b-1 style-b-2]
            }
          }
        )
      end

      it 'invokes rubocop 3 times' do
        runner.run

        expect(RuboCop::Nightly::Runtime).to have_received(:execute).exactly(3).times
      end

      it 'covers every supported style across the generated variants' do
        styles = configuration.variants.map { it.dig('Department/CopName1', 'EnforcedStyle') }

        expect(styles).to match_array(%w[style-a-1 style-a-2 style-a-3])
      end
    end

    context 'with detected bugs' do
      let(:configuration) do
        RuboCop::Nightly::Configuration.build({ 'Department/CopName1' => { 'Enabled' => true } })
      end

      let(:stderr) do
        <<~TXT
          Inspecting 1 file
          Scanning bug.rb
          An error occurred while Style/MethodCallWithoutArgsParentheses cop was inspecting bug.rb:1:15.
          undefined method `name' for an instance of RuboCop::AST::SendNode
        TXT
      end

      before do
        allow(RuboCop::Nightly::Runtime).to receive(:execute).and_return(
          ['', stderr, instance_double(Process::Status, success?: true, exitstatus: 0)]
        )
      end

      it 'reports the offending cop and source pointer' do
        expect(runner.run.cop_errors).to contain_exactly(
          described_class::ErrorDetails.new(
            cop_name: 'Style/MethodCallWithoutArgsParentheses',
            source_pointer: 'bug.rb:1:15'
          )
        )
      end

      it 'persists a reproducible configuration alongside the report' do
        allow(RuboCop::Nightly.logger).to receive(:error)

        runner.run

        expect(RuboCop::Nightly.logger).to have_received(:error).with(%r{reproductions/variant-0.*bug\.rb:1:15})
      end

      it 'preserves stdout, stderr, the config and the targets', :aggregate_failures do
        allow(RuboCop::Nightly::Runtime).to receive(:execute).and_return(
          ['inspecting things', stderr, instance_double(Process::Status, success?: true, exitstatus: 0)]
        )

        runner.run
        directory = reproduction_directories.fetch(0)

        expect(File.read(directory.join('stdout.log'))).to eq('inspecting things')
        expect(File.read(directory.join('stderr.log'))).to eq(stderr)
        expect(File.read(directory.join('targets.txt'))).to eq("/a.rb\n")
        expect(YAML.safe_load_file(directory.join('configuration.yml'))).to include('Department/CopName1')
      end

      it 'does not let one batch overwrite another batch reproduction', :aggregate_failures do
        described_class.new(['/a.rb'], configuration: configuration).run
        described_class.new(['/b.rb'], configuration: configuration).run

        expect(reproduction_directories.size).to eq(2)
        expect(reproduction_directories.map { File.read(it.join('targets.txt')) })
          .to contain_exactly("/a.rb\n", "/b.rb\n")
      end

      it 'does not re-report an error already seen in an earlier batch' do
        findings = RuboCop::Nightly::Commands::Fuzzer::Findings.new
        described_class.new(['/a.rb'], configuration: configuration, findings: findings).run

        expect { described_class.new(['/b.rb'], configuration: configuration, findings: findings).run }
          .not_to change(findings.cop_errors, :size)
      end
    end

    context 'when RuboCop emits an unrecognised error line' do
      let(:configuration) do
        RuboCop::Nightly::Configuration.build({ 'Department/CopName1' => { 'Enabled' => true } })
      end

      before do
        allow(RuboCop::Nightly::Runtime).to receive(:execute).and_return(
          ['', "An error occurred while walking the tree\n",
           instance_double(Process::Status, success?: true, exitstatus: 0)]
        )
      end

      it 'ignores it instead of raising on a nil MatchData' do
        expect { runner.run }.not_to raise_error
      end
    end

    context 'with a batch deadline' do
      let(:configuration) do
        RuboCop::Nightly::Configuration.build(
          { 'Department/CopName1' => { 'Enabled' => true, 'SupportedStyles' => %w[a b c] } }
        )
      end

      it 'stops once the deadline has passed' do
        allow(RuboCop::Nightly::Runtime).to receive(:execute) do
          sleep 0.05
          clean_run
        end

        expect { described_class.new(['/a.rb'], configuration: configuration, timeout: 0.06).run }
          .to raise_error(RuboCop::Nightly::ExecutionTimeout)
      end
    end
  end

  describe 'Ruby warnings' do
    let(:configuration) do
      RuboCop::Nightly::Configuration.build({ 'Department/CopName1' => { 'Enabled' => true } })
    end

    def run_with_stderr(stderr)
      allow(RuboCop::Nightly::Runtime).to receive(:execute).and_return(
        ['', stderr, instance_double(Process::Status, success?: true, exitstatus: 0)]
      )

      described_class.new(['/a.rb'], configuration: configuration).run
    end

    it 'asks the child for verbose mode' do
      described_class.new(['/a.rb'], configuration: configuration).run

      expect(RuboCop::Nightly::Runtime).to have_received(:execute).with(any_args, hash_including(warnings: true))
    end

    it 'collects a warning RuboCop emitted while inspecting' do
      findings = run_with_stderr("/gems/rubocop/lib/rubocop/cop/style/x.rb:12: warning: method redefined\n")

      expect(findings.warnings.map(&:message)).to contain_exactly('method redefined')
    end

    it 'masks the Bundler checkout revision so one warning is not counted twice' do
      findings = run_with_stderr(
        "/gems/rubocop-389a084d5225/lib/x.rb:1: warning: boom\n" \
        "/gems/rubocop-4555c49f3163/lib/x.rb:9: warning: boom\n"
      )

      expect(findings.warnings.size).to eq(1)
    end

    # A warning is worth reading, but a noisy dependency must not turn an otherwise clean
    # night red.
    it 'does not treat a warning as a defect' do
      findings = run_with_stderr("/gems/rubocop/lib/x.rb:12: warning: method redefined\n")

      expect(findings).to be_empty
    end

    it 'ignores lines that are not warnings' do
      findings = run_with_stderr("Inspecting 1 file\nwarning-ish but not a warning\n")

      expect(findings.warnings).to be_empty
    end
  end

  describe 'autocorrect mode' do
    let(:configuration) do
      RuboCop::Nightly::Configuration.build({ 'Department/CopName1' => { 'Enabled' => true } })
    end

    it 'does not ask RuboCop to correct anything by default' do
      described_class.new(['/a.rb'], configuration: configuration).run

      expect(executed_arguments).not_to include('--autocorrect-all')
    end

    it 'asks RuboCop to correct when it is on' do
      described_class.new(['/a.rb'], configuration: configuration, autocorrect: true).run

      expect(executed_arguments).to include('--autocorrect-all')
    end

    # The corpus is a set of git checkouts every later run depends on, so a correcting run is
    # pointed at copies instead.
    it 'points RuboCop at something other than the corpus path' do
      corpus = Pathname(Dir.mktmpdir('rubocop-nightly-corpus'))
      corpus.join('a.rb').write("x = 1\n")

      described_class.new([corpus.join('a.rb').to_s], configuration: configuration, autocorrect: true).run

      expect(executed_arguments).not_to include(corpus.join('a.rb').to_s)
    ensure
      FileUtils.remove_entry(corpus)
    end

    it 'reports an infinite correction loop, which never reaches the cop-error path' do
      allow(RuboCop::Nightly::Runtime).to receive(:execute).and_return(
        ['', "Infinite loop detected in /a.rb and caused by Style/A -> Style/B\n",
         instance_double(Process::Status, success?: true, exitstatus: 0)]
      )

      findings = described_class.new(['/a.rb'], configuration: configuration).run

      expect(findings.correction_loops.map(&:cop_names)).to contain_exactly('Style/A -> Style/B')
    end

    it 'counts a correction loop as a defect' do
      allow(RuboCop::Nightly::Runtime).to receive(:execute).and_return(
        ['', "Infinite loop detected in /a.rb and caused by Style/A\n",
         instance_double(Process::Status, success?: true, exitstatus: 0)]
      )

      expect(described_class.new(['/a.rb'], configuration: configuration).run).not_to be_empty
    end

    it 'tolerates a loop message with no path or cause' do
      allow(RuboCop::Nightly::Runtime).to receive(:execute).and_return(
        ['', "Infinite loop detected\n", instance_double(Process::Status, success?: true, exitstatus: 0)]
      )

      findings = described_class.new(['/a.rb'], configuration: configuration).run

      expect(findings.correction_loops.size).to eq(1)
    end
  end

  describe '.build_configuration' do
    it 'raises an actionable error when the gems directory is missing' do
      FileUtils.remove_entry(RuboCop::Nightly::Runtime.gems_data_directory)

      expect { described_class.build_configuration }
        .to raise_error(RuboCop::Nightly::ConfigurationError, /rake gems:install/)
    end
  end
end
