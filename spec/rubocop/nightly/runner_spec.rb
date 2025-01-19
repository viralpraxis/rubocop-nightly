# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Runner do
  describe '#run' do
    subject(:runner) do
      described_class.new(['/a.rb'], configuration)
    end

    before do
      allow(RuboCop::Nightly.logger).to receive(:warn)
      allow(RuboCop::Nightly.logger).to receive(:debug)
      allow(Open3).to receive(:capture3).and_return(
        ['', '', instance_double(Process::Status, success?: true, exitstatus: 0)]
      )
    end

    context 'when configuration does not have supported styles' do
      let(:configuration) do
        RuboCop::Nightly::Configuration.build(
          {
            'Department/CopName1' => { 'Enabled' => true },
            'Department/CopName2' => { 'Enabled' => true }
          }
        )
      end

      it 'invokes rubocop once' do # rubocop:disable RSpec/ExampleLength
        runner.run

        expect(Open3).to have_received(:capture3)
          .with(
            'bundle', 'exec', 'rubocop', '/a.rb', '-c',
            '/tmp/rubocop-nightly-configuration.yml', '--format', 'RuboCop::Nightly::NullFormatter',
            '--cache', 'false', '-r',
            Pathname.new("#{__dir__}/../../../lib/rubocop/nightly/null_formatter.rb").cleanpath.to_s
          )
          .once
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

      it 'invokes rubocop 3 times' do # rubocop:disable RSpec/ExampleLength
        runner.run

        expect(Open3).to have_received(:capture3)
          .with(
            'bundle', 'exec', 'rubocop', '/a.rb', '-c',
            '/tmp/rubocop-nightly-configuration.yml', '--format', 'RuboCop::Nightly::NullFormatter',
            '--cache', 'false', '-r',
            Pathname.new("#{__dir__}/../../../lib/rubocop/nightly/null_formatter.rb").cleanpath.to_s
          )
          .exactly(3).times
      end
    end

    context 'with detected bugs' do
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

      before do
        allow(Open3).to receive(:capture3).and_return(
          [
            '',
            <<~TXT,
              Inspecting 1 file
              Scanning bug.rb
              An error occurred while Style/MethodCallWithoutArgsParentheses cop was inspecting bug.rb:1:15.
              undefined method `name' for an instance of RuboCop::AST::SendNode
              lib/rubocop/cop/style/method_call_without_args_parentheses.rb:111:in `block in variable_in_mass_assignment?'
              lib/rubocop/cop/style/method_call_without_args_parentheses.rb:110:in `any?'
              lib/rubocop/cop/style/method_call_without_args_parentheses.rb:110:in `variable_in_mass_assignment?'
              lib/rubocop/cop/style/method_call_without_args_parentheses.rb:75:in `block in same_name_assignment?'
              lib/rubocop/cop/style/method_call_without_args_parentheses.rb:105:in `block in any_assignment?'
            TXT
            instance_double(Process::Status, success?: true, exitstatus: 0)
          ]
        )
      end

      it 'invokes rubocop 3 times' do # rubocop:disable RSpec/ExampleLength
        runner.run

        expect(Open3).to have_received(:capture3)
          .with(
            'bundle', 'exec', 'rubocop', '/a.rb', '-c',
            '/tmp/rubocop-nightly-configuration.yml', '--format', 'RuboCop::Nightly::NullFormatter',
            '--cache', 'false', '-r',
            Pathname.new("#{__dir__}/../../../lib/rubocop/nightly/null_formatter.rb").cleanpath.to_s
          )
          .exactly(3).times
      end
    end
  end
end
