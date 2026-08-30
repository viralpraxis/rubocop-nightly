# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Commands::Fuzzer::CorrectionCheck do
  let(:root) { Pathname(Dir.mktmpdir('rubocop-nightly-correction')) }
  let(:original) { root.join('original.rb') }
  let(:copy) { root.join('copy.rb') }

  after { FileUtils.remove_entry(root) }

  def check = described_class.call({ copy.to_s => original.to_s }, target_ruby_version: 3.4)

  it 'says nothing when the correction still parses' do
    original.write("def foo\n  1\nend\n")
    copy.write("def foo\n  2\nend\n")

    expect(check).to be_empty
  end

  it 'reports a correction that no longer parses', :aggregate_failures do
    original.write("def foo\n  1\nend\n")
    copy.write("def foo\n  1\n")

    expect(check.size).to eq(1)
    expect(check.fetch(0).path).to eq(original.to_s)
  end

  it 'carries the parse error across as the diagnostic' do
    original.write("x = 1\n")
    copy.write("x = \n")

    expect(check.fetch(0).diagnostic).to include('expected an expression')
  end

  # The differential guard: RuboCop cannot be blamed for source that never parsed to begin with,
  # and without this every unparseable corpus file would be reported as a broken correction.
  it 'ignores a file that did not parse before the correction either' do
    original.write("def foo\n")
    copy.write("def bar\n")

    expect(check).to be_empty
  end

  it 'does nothing when no file was rewritten' do
    expect(described_class.call({}, target_ruby_version: 3.4)).to be_empty
  end

  it 'falls back to the newest grammar when the target version is one Prism does not know' do
    original.write("x = 1\n")
    copy.write("x = \n")

    expect(described_class.call({ copy.to_s => original.to_s }, target_ruby_version: 9.9).size).to eq(1)
  end

  it 'tolerates a missing target version' do
    original.write("x = 1\n")
    copy.write("x = \n")

    expect(described_class.call({ copy.to_s => original.to_s }, target_ruby_version: nil).size).to eq(1)
  end

  it 'skips a copy that has gone missing' do
    original.write("x = 1\n")

    expect(check).to be_empty
  end
end
