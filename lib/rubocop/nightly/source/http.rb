# frozen_string_literal: true

require 'net/http'
require 'uri'

module RuboCop
  module Nightly
    module Source
      # Plain GET with the timeouts and redirect following a remote source needs, kept apart
      # from the sources themselves so those deal only in feeds, archives and paths.
      module Http
        OPEN_TIMEOUT = 10
        READ_TIMEOUT = 60
        MAX_REDIRECTS = 5

        private_constant(*constants(false))

        private

        def get(uri, redirects_left: MAX_REDIRECTS)
          response = Net::HTTP.start(
            uri.host, uri.port,
            use_ssl: uri.scheme == 'https', open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT
          ) { it.request(Net::HTTP::Get.new(uri)) }

          case response
          when Net::HTTPSuccess then response.body
          when Net::HTTPRedirection then follow_redirect(uri, response, redirects_left)
          else raise ExecutionError, "GET #{uri} failed with #{response.code} #{response.message}"
          end
        end

        def follow_redirect(uri, response, redirects_left)
          raise ExecutionError, "too many redirects for #{uri}" if redirects_left.zero?

          get(URI.join(uri.to_s, response.fetch('location')), redirects_left: redirects_left - 1)
        end
      end
    end
  end
end
