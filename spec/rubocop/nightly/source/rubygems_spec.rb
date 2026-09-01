# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Source::Rubygems do
  subject(:source) { described_class.new(base_path: base_path) }

  let(:base_path) { Dir.mktmpdir('rubocop-nightly-rubygems') }
  let(:today) { Date.today.to_s }

  after { FileUtils.remove_entry(base_path) }

  # `get` dispatches with `case/when`, which is `Net::HTTPSuccess === response`; a verifying
  # double is not an instance of it, so these are real response objects.
  def ok(body = '')
    Net::HTTPOK.new('1.1', '200', 'OK').tap { allow(it).to receive(:body).and_return(body) }
  end

  def redirect_to(location)
    Net::HTTPFound.new('1.1', '302', 'Found').tap do |resp|
      allow(resp).to receive(:fetch).with('location').and_return(location)
    end
  end

  def failure(code = '404', message = 'Not Found')
    Net::HTTPNotFound.new('1.1', code, message)
  end

  def stub_http(*responses)
    allow(Net::HTTP).to receive(:start).and_return(*responses)
  end

  def feed(*gems) = JSON.generate(gems)

  def entry(name: 'thing', number: '1.0.0', platform: 'ruby', created: Date.today.to_s, **rest)
    { 'name' => name, 'number' => number, 'platform' => platform,
      'version_created_at' => created }.merge(rest)
  end

  describe '#fetch' do
    it 'returns an empty array when nothing was published in the window' do
      stub_http(ok(feed))

      expect(source.fetch).to eq([])
    end

    it 'skips entries published outside the window' do
      stub_http(ok(feed(entry(created: (Date.today - 30).to_s))))

      expect(source.fetch).to eq([])
    end

    it 'skips entries with no publication date' do
      stub_http(ok(feed(entry(created: nil))))

      expect(source.fetch).to eq([])
    end

    it 'skips entries with an unparseable publication date' do
      stub_http(ok(feed(entry(created: 'not a date'))))

      expect(source.fetch).to eq([])
    end

    it 'raises a descriptive error when the feed is not JSON' do
      stub_http(ok('<!DOCTYPE html>'))

      expect { source.fetch }.to raise_error(RuboCop::Nightly::ExecutionError, /unparseable/)
    end

    it 'raises when the feed request fails' do
      stub_http(failure('503', 'Service Unavailable'))

      expect { source.fetch }.to raise_error(RuboCop::Nightly::ExecutionError, /503/)
    end

    it 'reuses an already extracted gem without downloading again', :aggregate_failures do
      FileUtils.mkdir_p(File.join(base_path, 'thing', '1.0.0'))
      stub_http(ok(feed(entry)))

      expect(source.fetch).to eq([File.join(base_path, 'thing', '1.0.0')])
      expect(Net::HTTP).to have_received(:start).once
    end

    it 'keeps platform variants apart' do
      FileUtils.mkdir_p(File.join(base_path, 'thing', '1.0.0'))
      FileUtils.mkdir_p(File.join(base_path, 'thing', '1.0.0-x86_64-linux'))
      stub_http(ok(feed(entry, entry(platform: 'x86_64-linux'))))

      expect(source.fetch.size).to eq(2)
    end

    it 'ignores entries with no name or version' do
      stub_http(ok(feed(entry(name: nil), entry(number: nil))))

      expect(source.fetch).to eq([])
    end

    it 'reports a failed download and carries on', :aggregate_failures do
      allow(RuboCop::Nightly.logger).to receive(:warn)
      stub_http(ok(feed(entry)),
                failure)

      expect(source.fetch).to eq([])
      expect(RuboCop::Nightly.logger).to have_received(:warn).with(/Error processing gem thing/)
    end
  end

  describe 'limit' do
    def already_extracted(*names)
      names.each { |name| FileUtils.mkdir_p(File.join(base_path, name, '1.0.0')) }
    end

    def extracted_path(name) = File.join(base_path, name, '1.0.0')

    it 'keeps only the most recently published gems' do
      already_extracted('a', 'b', 'c')
      stub_http(ok(feed(entry(name: 'a'), entry(name: 'b'), entry(name: 'c'))))

      expect(described_class.new(base_path: base_path, limit: 2).fetch)
        .to eq([extracted_path('a'), extracted_path('b')])
    end

    it 'keeps every gem in the window when no limit is given' do
      already_extracted('a', 'b', 'c')
      stub_http(ok(feed(entry(name: 'a'), entry(name: 'b'), entry(name: 'c'))))

      expect(source.fetch.size).to eq(3)
    end

    it 'returns fewer than the limit when the window holds fewer gems' do
      already_extracted('a')
      stub_http(ok(feed(entry(name: 'a'))))

      expect(described_class.new(base_path: base_path, limit: 20).fetch).to eq([extracted_path('a')])
    end

    # The limit is applied after the publication window, so a stale entry at the head of the
    # feed cannot consume one of the slots.
    it 'does not count entries published outside the window' do
      already_extracted('a', 'b')
      stub_http(ok(feed(entry(name: 'stale', created: (Date.today - 30).to_s),
                        entry(name: 'a'), entry(name: 'b'))))

      expect(described_class.new(base_path: base_path, limit: 2).fetch)
        .to eq([extracted_path('a'), extracted_path('b')])
    end
  end

  describe 'checksum verification' do
    it 'rejects a payload whose digest does not match', :aggregate_failures do
      allow(RuboCop::Nightly.logger).to receive(:warn)
      stub_http(ok(feed(entry(sha: 'deadbeef'))),
                ok('payload'))

      expect(source.fetch).to eq([])
      expect(RuboCop::Nightly.logger).to have_received(:warn).with(/checksum mismatch/)
    end

    it 'accepts a payload whose digest matches' do
      body = 'payload'
      allow(RuboCop::Nightly.logger).to receive(:warn)
      stub_http(ok(feed(entry(sha: Digest::SHA256.hexdigest(body)))),
                ok(body))

      source.fetch

      expect(RuboCop::Nightly.logger).not_to have_received(:warn).with(/checksum mismatch/)
    end
  end

  describe 'redirects' do
    it 'follows a redirect to the final location' do
      allow(RuboCop::Nightly.logger).to receive(:warn)
      redirect = redirect_to('https://example.com/final.gem')
      stub_http(ok(feed(entry)), redirect,
                ok('not a gem'))

      source.fetch

      expect(Net::HTTP).to have_received(:start).exactly(3).times
    end

    it 'gives up after too many redirects', :aggregate_failures do
      allow(RuboCop::Nightly.logger).to receive(:warn)
      redirect = redirect_to('https://example.com/loop.gem')
      stub_http(ok(feed(entry)), *Array.new(8) { redirect })

      expect(source.fetch).to eq([])
      expect(RuboCop::Nightly.logger).to have_received(:warn).with(/too many redirects/)
    end
  end
end
