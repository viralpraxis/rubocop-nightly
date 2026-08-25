# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Commands::Compare::Report do
  def offense(cop_name, line, message = 'msg')
    { 'cop_name' => cop_name, 'location' => { 'line' => line, 'column' => 1 }, 'message' => message }
  end

  def report(files) = { 'files' => files }

  def file(path, *offenses) = { 'path' => path, 'offenses' => offenses }

  def call(before, after) = described_class.call(before, after, source_directory_path: '/src')

  describe '.call' do
    it 'reports offenses present only in the newer run as new' do
      result = call(report([file('/src/a.rb')]), report([file('/src/a.rb', offense('Lint/Void', 1))]))

      expect(result.new_offenses.flat_map { it.last.to_a }.map(&:cop_name)).to eq(['Lint/Void'])
    end

    it 'reports offenses present only in the older run as removed' do
      result = call(report([file('/src/a.rb', offense('Lint/Void', 1))]), report([file('/src/a.rb')]))

      expect(result.removed_offenses.flat_map { it.last.to_a }.map(&:cop_name)).to eq(['Lint/Void'])
    end

    # The two revisions do not necessarily inspect the same files; this used to raise KeyError
    # after both expensive RuboCop runs had already completed.
    context 'when the two runs inspected different files' do
      it 'does not raise when a file exists only in the newer run' do
        expect { call(report([file('/src/a.rb')]), report([file('/src/a.rb'), file('/src/b.rb')])) }
          .not_to raise_error
      end

      it 'does not raise when a file exists only in the older run' do
        expect { call(report([file('/src/a.rb'), file('/src/b.rb')]), report([file('/src/a.rb')])) }
          .not_to raise_error
      end

      it 'reports offenses from a file the newer run stopped inspecting' do
        result = call(report([file('/src/gone.rb', offense('Lint/Void', 1))]), report([]))

        expect(result.removed_offenses.flat_map { it.last.to_a }.map(&:cop_name)).to eq(['Lint/Void'])
      end

      it 'reports offenses from a file only the newer run inspected' do
        result = call(report([]), report([file('/src/new.rb', offense('Lint/Void', 1))]))

        expect(result.new_offenses.flat_map { it.last.to_a }.map(&:cop_name)).to eq(['Lint/Void'])
      end
    end

    it 'treats identical offenses as unchanged' do
      identical = report([file('/src/a.rb', offense('Lint/Void', 1))])
      result = call(identical, identical)

      expect([result.new_offenses, result.removed_offenses]).to all(be_empty)
    end

    it 'ignores message-only differences' do
      result = call(
        report([file('/src/a.rb', offense('Lint/Void', 1, 'old wording'))]),
        report([file('/src/a.rb', offense('Lint/Void', 1, 'new wording'))])
      )

      expect([result.new_offenses, result.removed_offenses]).to all(be_empty)
    end
  end

  describe described_class::Offense do
    let(:location) { { 'line' => 1, 'column' => 1 } }

    it 'compares consistently across ==, eql? and hash', :aggregate_failures do
      one = described_class.new(cop_name: 'A/B', location:, message: 'x')
      two = described_class.new(cop_name: 'A/B', location:, message: 'y')

      expect(one).to eq(two)
      expect(one).to eql(two)
      expect(one.hash).to eq(two.hash)
      expect(Set[one, two].size).to eq(1)
    end

    it 'distinguishes different cops at the same location' do
      one = described_class.new(cop_name: 'A/B', location:, message: 'x')
      two = described_class.new(cop_name: 'A/C', location:, message: 'x')

      expect(one).not_to eq(two)
    end
  end
end
