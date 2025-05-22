# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Configuration::Traversal do
  describe '.call' do
    def perform(cops, dependencies) = described_class.call(cops, dependencies)

    def expect_be_a_total_configuration(configuration, total:)
      expect(configuration.size).to eq(total)

      cops.each do |cop_name, cop_styles|
        expect(configuration.map { it.fetch(cop_name, {}).fetch('Attr', nil) }.compact.uniq)
          .to match_array(cop_styles.fetch('Attr', []))
      end
    end

    context 'without per-cop variations' do
      let(:cops) do
        {
          'Dep-1/Cop-1' => {},
          'Dep-1/Cop-2' => {}
        }
      end

      let(:dependencies) { {} }

      specify do
        expect(perform(cops, dependencies)).to eq(
          [{ 'Dep-1/Cop-1' => {}, 'Dep-1/Cop-2' => {} }]
        )
      end
    end

    context 'with two independent cops with variations' do
      let(:cops) do
        {
          'Dep-1/Cop-1' => { 'Attr' => %w[a b] },
          'Dep-1/Cop-2' => { 'Attr' => %w[c d] }
        }
      end

      let(:dependencies) { {} }

      specify do
        expect(perform(cops, dependencies)).to contain_exactly(
          { 'Dep-1/Cop-1' => { 'Attr' => 'a' }, 'Dep-1/Cop-2' => { 'Attr' => 'c' } },
          { 'Dep-1/Cop-1' => { 'Attr' => 'b' }, 'Dep-1/Cop-2' => { 'Attr' => 'd' } }
        )
      end
    end

    context 'with two dependent cops with variations' do
      let(:cops) do
        {
          'Dep-1/Cop-1' => { 'Attr' => %w[a b] },
          'Dep-1/Cop-2' => { 'Attr' => %w[c d] }
        }
      end

      let(:dependencies) { { 'Dep-1/Cop-1' => ['Dep1/Cop-2'] } }

      specify do
        expect(perform(cops, dependencies)).to contain_exactly(
          { 'Dep-1/Cop-1' => { 'Attr' => 'a' }, 'Dep-1/Cop-2' => { 'Attr' => 'c' } },
          { 'Dep-1/Cop-1' => { 'Attr' => 'b' }, 'Dep-1/Cop-2' => { 'Attr' => 'd' } }
        )
      end
    end

    context 'with two independent cops with only one having varition' do
      let(:cops) do
        {
          'Dep-1/Cop-1' => { 'Attr' => %w[a b] },
          'Dep-1/Cop-2' => {}
        }
      end

      let(:dependencies) { {} }

      specify do
        expect(perform(cops, dependencies)).to contain_exactly(
          { 'Dep-1/Cop-1' => { 'Attr' => 'a' }, 'Dep-1/Cop-2' => {} },
          { 'Dep-1/Cop-1' => { 'Attr' => 'b' } }
        )
      end
    end

    context 'with two distinct independent cop groups' do
      let(:cops) do
        {
          'Dep-1/Cop-1' => { 'Attr' => ['1-1-1', '1-1-2'] },
          'Dep-1/Cop-2' => { 'Attr' => ['1-2-1', '1-2-2'] },
          'Dep-2/Cop-1' => { 'Attr' => ['2-1-1', '2-1-2'] },
          'Dep-2/Cop-2' => { 'Attr' => ['2-2-1', '2-2-2'] }
        }
      end

      let(:dependencies) do
        {
          'Dep-1/Cop-1' => ['Dep-1/Cop-2'],
          'Dep-2/Cop-1' => ['Dep-2/Cop-2']
        }
      end

      it { expect_be_a_total_configuration(perform(cops, dependencies), total: 4) }
    end

    context 'with dependency of length 3' do
      let(:cops) do
        {
          'Cop-1' => { 'Attr' => ['11', '12'] },
          'Cop-2' => { 'Attr' => ['21', '22'] },
          'Cop-3' => { 'Attr' => ['31', '32'] },
        }
      end

      let(:dependencies) do
        {
          'Cop-1' => ['Cop-2'],
          'Cop-2' => ['Cop-3']
        }
      end

      it { expect_be_a_total_configuration(perform(cops, dependencies), total: 4) }
    end

    context 'with cyclic dependency of length 3' do
      let(:cops) do
        {
          'Cop-1' => { 'Attr' => ['11', '12'] },
          'Cop-2' => { 'Attr' => ['21', '22'] },
          'Cop-3' => { 'Attr' => ['31', '32'] },
        }
      end

      let(:dependencies) do
        {
          'Cop-1' => %w[Cop-2],
          'Cop-2' => %w[Cop-3],
          'Cop-3' => %w[Cop-1]
        }
      end

      it { expect_be_a_total_configuration(perform(cops, dependencies), total: 6) }
    end
  end
end
