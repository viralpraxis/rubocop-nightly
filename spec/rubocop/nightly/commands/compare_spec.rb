# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Commands::Compare do
  subject(:command) { described_class.new(options) }

  let(:options) do
    RuboCop::Nightly::CLI::Parser.parse(%w[compare --from a --to b --source https://example.com/x.git])
  end

  def offense(cop_name, line, message = 'boom')
    RuboCop::Nightly::Commands::Compare::Report::Offense.new(
      cop_name: cop_name, location: { 'line' => line, 'column' => 3 }, message: message
    )
  end

  def report(removed: [], added: [], root: '/src')
    instance_double(
      RuboCop::Nightly::Commands::Compare::Report,
      removed_offenses: removed, new_offenses: added, source_directory_path: Pathname(root)
    )
  end

  before { allow(RuboCop::Nightly::Commands::Compare::Runner).to receive(:call).and_return(built_report) }

  context 'when the revisions agree' do
    let(:built_report) { report }

    it 'says so and reports no difference', :aggregate_failures do
      expect { expect(command.call).to be(true) }.to output(/No offense differences/).to_stdout
    end
  end

  context 'with new offenses' do
    let(:built_report) { report(added: [['/src/a.rb', [offense('Lint/Void', 4)]]]) }

    it 'reports them and signals a difference', :aggregate_failures do
      expect { expect(command.call).to be(false) }.to output(/New offenses: \(1\)/).to_stdout
    end

    it 'renders the path relative to the analysed source' do
      expect { command.call }.to output(%r{\[Lint/Void\] a\.rb:4:3: boom}).to_stdout
    end
  end

  context 'with removed offenses' do
    let(:built_report) { report(removed: [['/src/a.rb', [offense('Lint/Void', 1)]]]) }

    it 'reports them', :aggregate_failures do
      expect { expect(command.call).to be(false) }.to output(/Removed offenses: \(1\)/).to_stdout
    end
  end

  context 'when RuboCop reported a relative path' do
    let(:built_report) { report(added: [['relative/a.rb', [offense('Lint/Void', 2)]]]) }

    it 'leaves it alone' do
      expect { command.call }.to output(%r{relative/a\.rb:2:3}).to_stdout
    end
  end

  context 'when the path is outside the analysed source' do
    let(:built_report) { report(added: [['/elsewhere/a.rb', [offense('Lint/Void', 2)]]], root: 'relative-root') }

    it 'falls back to the path as reported' do
      expect { command.call }.to output(%r{/elsewhere/a\.rb:2:3}).to_stdout
    end
  end

  context 'with several offenses in one file' do
    let(:built_report) { report(added: [['/src/a.rb', [offense('Lint/Void', 1), offense('Lint/Void', 2)]]]) }

    it 'counts them all' do
      expect { command.call }.to output(/New offenses: \(2\)/).to_stdout
    end
  end
end
