# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Configuration::Traversal do
  describe '.call' do
    def perform(cops, dependencies) = described_class.call(cops, dependencies)

    def expect_be_a_total_configuration(configuration, total:)
      expect(configuration.size).to eq(total)

      cops.each do |cop_name, cop_styles|
        expect(configuration.map { it.dig(cop_name, 'Attr') }.compact.uniq)
          .to match_array(cop_styles.fetch('Attr', []))
      end

      expect_pairwise_coverage(configuration)
    end

    # Exploring dependent cops jointly is the entire point of passing `dependencies` in, so
    # assert it: every (cop value, dependency value) pairing must occur in some variant.
    def expect_pairwise_coverage(configuration)
      each_dependency_pair do |cop_name, dependency_name|
        expect(observed_pairs(configuration, cop_name, dependency_name))
          .to match_array(expected_pairs(cop_name, dependency_name))
      end
    end

    def each_dependency_pair(&)
      dependencies.each { |cop_name, names| Array(names).each { yield(cop_name, it) } }
    end

    def expected_pairs(cop_name, dependency_name)
      styles_of(cop_name).product(styles_of(dependency_name))
    end

    def observed_pairs(configuration, cop_name, dependency_name)
      configuration.filter_map do |variant|
        pair = [variant.dig(cop_name, 'Attr'), variant.dig(dependency_name, 'Attr')]
        pair unless pair.any?(&:nil?)
      end.uniq
    end

    def styles_of(cop_name) = cops.fetch(cop_name).fetch('Attr', [])

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

      let(:dependencies) { { 'Dep-1/Cop-1' => ['Dep-1/Cop-2'] } }

      # Dependent cops are explored jointly, so every pairing of their styles is covered —
      # unlike the independent case above, which only needs two variants.
      specify do
        expect(perform(cops, dependencies)).to contain_exactly(
          { 'Dep-1/Cop-1' => { 'Attr' => 'a' }, 'Dep-1/Cop-2' => { 'Attr' => 'c' } },
          { 'Dep-1/Cop-1' => { 'Attr' => 'a' }, 'Dep-1/Cop-2' => { 'Attr' => 'd' } },
          { 'Dep-1/Cop-1' => { 'Attr' => 'b' }, 'Dep-1/Cop-2' => { 'Attr' => 'c' } },
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

    # Such a cop contributed only its dependencies' keys, so no variant ever enabled it.
    context 'with a cop that has dependencies but no attributes of its own' do
      let(:cops) do
        {
          'Dep-1/Plain' => {},
          'Dep-1/Styled' => { 'Attr' => %w[a b] }
        }
      end

      let(:dependencies) { { 'Dep-1/Plain' => ['Dep-1/Styled'] } }

      it 'still appears in the generated configuration' do
        expect(perform(cops, dependencies).select { it.key?('Dep-1/Plain') }).not_to be_empty
      end

      it 'still covers every style of its dependency' do
        expect(perform(cops, dependencies).filter_map { it.dig('Dep-1/Styled', 'Attr') }.uniq)
          .to match_array(%w[a b])
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
          'Cop-1' => { 'Attr' => %w[11 12] },
          'Cop-2' => { 'Attr' => %w[21 22] },
          'Cop-3' => { 'Attr' => %w[31 32] }
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

    # Exhaustively crossing one cop's own axes is what drives the variant count, and each
    # variant is a full RuboCop pass over the corpus.
    context 'with a cop that has three attributes' do
      subject(:configuration) { perform(cops, dependencies) }

      let(:cops) do
        {
          'Layout/HashAlignment' => {
            'RocketStyles' => %w[key separator table],
            'ColonStyles' => %w[key separator table],
            'LastArgumentStyles' => %w[always_inspect always_ignore ignore_implicit ignore_explicit]
          }
        }
      end

      let(:dependencies) { {} }

      # 36 rows exhaustively; 12 is the pairwise optimum here, since the 3-value and
      # 4-value attributes alone contribute 12 distinct pairs and each row covers one.
      it 'needs 12 variants rather than the 36-row cross product' do
        expect(configuration.size).to eq(12)
      end

      it 'still covers every value of every attribute', :aggregate_failures do
        cops.fetch('Layout/HashAlignment').each do |attribute, values|
          expect(configuration.filter_map { it.dig('Layout/HashAlignment', attribute) }.uniq)
            .to match_array(values)
        end
      end

      it 'covers every pair of values across every pair of attributes' do
        attributes = cops.fetch('Layout/HashAlignment')

        uncovered = attributes.keys.combination(2).flat_map do |left, right|
          attributes[left].product(attributes[right]).reject do |left_value, right_value|
            configuration.any? do |variant|
              variant.dig('Layout/HashAlignment', left) == left_value &&
                variant.dig('Layout/HashAlignment', right) == right_value
            end
          end
        end

        expect(uncovered).to be_empty
      end
    end

    context 'with cyclic dependency of length 3' do
      let(:cops) do
        {
          'Cop-1' => { 'Attr' => %w[11 12] },
          'Cop-2' => { 'Attr' => %w[21 22] },
          'Cop-3' => { 'Attr' => %w[31 32] }
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
