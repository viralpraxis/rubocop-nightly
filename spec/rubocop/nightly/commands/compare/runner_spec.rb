# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Commands::Compare::Runner do
  let(:specification) { RuboCop::Nightly::Commands::Compare::RevisionSpecification.parse(revision) }
  let(:revision) { 'abc123' }
  let(:directory) { Pathname(Dir.mktmpdir('rubocop-nightly-compare')) }

  after { FileUtils.remove_entry(directory) if directory.exist? }

  describe '.resolve_revision' do
    it 'uses the remote HEAD when no revision was given' do
      expect(described_class.resolve_revision(nil)).to eq('origin/HEAD')
    end

    it 'prefers the remote branch when one exists' do
      allow(described_class).to receive(:remote_branch?).and_return(true)

      expect(described_class.resolve_revision('main')).to eq('origin/main')
    end

    it 'falls back to the bare revision for a SHA or tag' do
      allow(described_class).to receive(:remote_branch?).and_return(false)

      expect(described_class.resolve_revision('abc123')).to eq('abc123')
    end
  end

  describe '.parse_report' do
    let(:runtime) { specification }

    it 'parses a report produced alongside offenses' do
      status = instance_double(Process::Status, exitstatus: 1)

      expect(described_class.parse_report('{"files":[]}', '', status, runtime)).to eq('files' => [])
    end

    it 'raises when RuboCop failed fatally' do
      status = instance_double(Process::Status, exitstatus: 2)

      expect { described_class.parse_report('', 'boom', status, runtime) }
        .to raise_error(RuboCop::Nightly::ExecutionError, /failed: boom/)
    end

    it 'raises when the report is not JSON' do
      status = instance_double(Process::Status, exitstatus: 0)

      expect { described_class.parse_report('<html>', '', status, runtime) }
        .to raise_error(RuboCop::Nightly::ExecutionError, /unparseable/)
    end
  end

  describe '.clone' do
    before { allow(FileUtils).to receive(:rm_rf) }

    it 'asks for a blobless clone when requested' do
      allow(described_class).to receive(:system).and_return(true)

      described_class.clone(directory, 'https://example.com/x.git', filter_blobs: true)

      expect(described_class).to have_received(:system).with('git', 'clone', '--filter=blob:none', '--',
                                                             'https://example.com/x.git', directory.to_s, out: File::NULL)
    end

    it 'retries without the filter when the server refuses it' do
      allow(described_class).to receive(:system).and_return(false, true)

      described_class.clone(directory, 'https://example.com/x.git', filter_blobs: true)

      expect(described_class).to have_received(:system).twice
    end

    it 'does not retry when the plain clone succeeded' do
      allow(described_class).to receive(:system).and_return(true)

      described_class.clone(directory, 'https://example.com/x.git')

      expect(described_class).to have_received(:system).once
    end
  end

  describe '.materialize' do
    before do
      allow(described_class).to receive_messages(clone: true, resolve_revision: 'abc123')
      allow(described_class).to receive(:system).and_return(true)
    end

    it 'clones when the directory holds no repository' do
      described_class.materialize(directory, specification)

      expect(described_class).to have_received(:clone)
    end

    it 'skips cloning when a repository is already there' do
      FileUtils.mkdir_p(directory.join('.git'))

      described_class.materialize(directory, specification)

      expect(described_class).not_to have_received(:clone)
    end

    it 'fetches and checks out on every run' do
      described_class.materialize(directory, specification)

      expect(described_class).to have_received(:system)
        .with('git', 'checkout', '--detach', 'abc123', exception: true, out: File::NULL)
    end
  end

  describe '.with_default_rubocop_configuration_file' do
    it 'removes the temporary file once the block returns' do
      allow(RuboCop::Nightly::Configuration).to receive(:build)
        .and_return(instance_double(RuboCop::Nightly::Configuration, to_yaml: "---\n"))
      seen = nil

      described_class.with_default_rubocop_configuration_file { |path| seen = path }

      expect(File.exist?(seen)).to be(false)
    end
  end
end
