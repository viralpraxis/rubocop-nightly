# frozen_string_literal: true

RSpec.describe RuboCop::Nightly do
  it 'has a version number' do
    expect(RuboCop::Nightly::VERSION).not_to be_nil
  end

  it 'does something useful' do
    expect(1.succ).to eq(2)
  end
end
