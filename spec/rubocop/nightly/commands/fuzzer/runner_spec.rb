# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Commands::Fuzzer::Runner do
  subject(:runner) { described_class.new(['/a.rb'], configuration: configuration) }

  # The runner chdirs into the gems data directory; give it a real one so these stay unit
  # tests instead of silently depending on `rake gems:install` having been run.
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
          require_plugins: true, timeout: nil
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
        expect(runner.run).to contain_exactly(
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

      # RuboCop's own output is the only record of what it actually said.
      it 'preserves stdout, stderr, the config and the targets', :aggregate_failures do
        allow(RuboCop::Nightly::Runtime).to receive(:execute).and_return(
          ['inspecting things', stderr, instance_double(Process::Status, success?: true, exitstatus: 0)]
        )

        runner.run
        directory = RuboCop::Nightly::Runtime.data_directory.join('fuzzer/reproductions/variant-0')

        expect(File.read(directory.join('stdout.log'))).to eq('inspecting things')
        expect(File.read(directory.join('stderr.log'))).to eq(stderr)
        expect(File.read(directory.join('targets.txt'))).to eq("/a.rb\n")
        expect(YAML.safe_load_file(directory.join('configuration.yml'))).to include('Department/CopName1')
      end

      it 'does not re-report an error already seen in an earlier batch' do
        errors = Set.new
        described_class.new(['/a.rb'], configuration: configuration, errors: errors).run

        expect { described_class.new(['/b.rb'], configuration: configuration, errors: errors).run }
          .not_to change(errors, :size)
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

  describe '.build_configuration' do
    it 'raises an actionable error when the gems directory is missing' do
      FileUtils.remove_entry(RuboCop::Nightly::Runtime.gems_data_directory)

      expect { described_class.build_configuration }
        .to raise_error(RuboCop::Nightly::ConfigurationError, /rake gems:install/)
    end
  end
end
