# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Commands::Fuzzer::Findings do
  let(:exception) do
    RuboCop::Nightly::Commands::Fuzzer::ErrorDetails.new(cop_name: 'Style/Thing', source_pointer: 'a.rb:1:1')
  end
  let(:broken) { described_class::BrokenCorrection.new(path: 'a.rb', diagnostic: 'boom') }
  let(:loop_finding) { described_class::CorrectionLoop.new(path: 'a.rb', cop_names: 'Style/Thing') }

  describe 'issue types' do
    it 'tags a cop crash' do
      expect(exception.issue_type).to eq('exception')
    end

    it 'tags a broken correction' do
      expect(broken.issue_type).to eq('broken-correction')
    end

    it 'tags a correction loop' do
      expect(loop_finding.issue_type).to eq('infinite-loop')
    end

    # `--only-show-types` validates against ISSUE_TYPES, so a kind whose tag drifted out of that
    # list would be impossible to filter for while still being reported.
    it 'lists exactly the tags the kinds actually report' do
      expect(described_class::ISSUE_TYPES)
        .to match_array([exception, broken, loop_finding].map(&:issue_type))
    end

    it 'has no duplicates' do
      expect(described_class::ISSUE_TYPES.uniq).to eq(described_class::ISSUE_TYPES)
    end
  end

  describe '#defects' do
    it 'counts the three reportable kinds but not warnings', :aggregate_failures do
      findings = described_class.new
      findings.cop_errors << exception
      findings.broken_corrections << broken
      findings.correction_loops << loop_finding
      findings.warnings << described_class::Warning.new(origin: 'x.rb', message: 'noisy')

      expect(findings.defects).to eq(3)
      expect(findings).not_to be_empty
    end
  end
end
