# Copyright 2011-2020, The Trustees of Indiana University and Northwestern
#   University.  Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed
#   under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
#   CONDITIONS OF ANY KIND, either express or implied. See the License for the
#   specific language governing permissions and limitations under the License.
# ---  END LICENSE_HEADER BLOCK  ---

require 'uri'
require 'net/http'
require 'json'

module Permalink

  extend ActiveSupport::Concern

  ActiveSupport::Reloader.to_prepare do
    ::Permalink.class_variable_set(:@@generator, @@generator) if @@generator
  end

  class Generator
    include Rails.application.routes.url_helpers
    attr_accessor :proc

    def initialize
      # Start LIBAVALON-91 
      @proc = Proc.new do |object, target|
        # Setup POST request
        request = Net::HTTP::Post.new(handle_service_uri, handle_request_headers)
        # POST request body as defined in umd-handle API v1.0.0.
        request.body = handle_request_body(object, target)

        # Make request
        use_ssl = (handle_service_uri.scheme == "https")
        response = Net::HTTP.start(handle_service_uri.hostname, handle_service_uri.port, use_ssl: use_ssl) do |http|
          http.request(request)
        end

        # Process response
        if response.is_a?(Net::HTTPSuccess)
          parsed_body = JSON.parse(response.body)
          handle_url = parsed_body['handle_url']
          Rails.logger.debug("Handle URL minted for: #{object.id}, URL: #{handle_url}")
          next handle_url # Return
        else
          # Log an error for unsuccessful response
          Rails.logger.error("Could not mint handle for object: #{object.id}")
          Rails.logger.error("Received a response status code of '#{response.code} - #{response.message}' from '#{handle_service_uri}'")
        end
      end
    end

    def handle_request_headers
      {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{handle_jwt_token}",
        'Accept' => 'application/json'
      }
    end

    def handle_request_body(object, local_url)
      {
        prefix: handle_prefix,
        url: local_url,
        repo: handle_repo,
        repo_id: "/media_objects/#{object.id}",
        description: object.title,
        notes: ''
      }.to_json
    end

    def handle_service_uri
      URI(ENV['UMD_HANDLE_SERVER_URL'])
    end

    def handle_jwt_token
      ENV['UMD_HANDLE_JWT_TOKEN']
    end

    def handle_prefix
      ENV['UMD_HANDLE_PREFIX']
    end

    def handle_repo
      ENV['UMD_HANDLE_REPO']
    end
    # End LIBAVALON-91 

    def avalon_url_for(obj)
      case obj
      when MediaObject then media_object_url(obj.id)
      when MasterFile  then id_section_media_object_url(obj.media_object.id, obj.id)
      else raise ArgumentError, "Cannot make permalink for #{obj.class}"
      end
    end

    def permalink_for(obj)
      @proc.call(obj, avalon_url_for(obj))
    end
  end

  @@generator = Generator.new
  def self.permalink_for(obj)
    @@generator.permalink_for(obj)
  end

  included do
    property :permalink, predicate: ::RDF::Vocab::DC.identifier, multiple: false do |index|
      index.as :stored_searchable
    end
  end

  def self.url_for(obj)
    @@generator.avalon_url_for(obj)
  end

  # Permalink.on_generate do |obj|
  #   permalink = (... generate permalink ...)
  #   return permalink
  # end
  def self.on_generate(&block)
    @@generator.proc = block
  end

  def permalink_with_query(query_vars = {})
    val = self.attributes['permalink']
    if val && query_vars.present?
      val = "#{val}?#{query_vars.to_query}"
    end
    val ? val.to_s : nil
  end

  # wrap this method; do not use this method as a callback
  # if it returns false it will skip the rest of the items in the callback chain

  def ensure_permalink!
    updated = false
    begin
      link = self.permalink
      if link.blank?
        link = Permalink.permalink_for(self)
      end

    rescue Exception => e
      link = nil
      logger.error "Permalink.permalink_for() raised an exception for #{self.inspect}: #{e}"
    end
    if link.present? and not (self.permalink == link)
      self.permalink = link
      updated = true
    end
    updated
  end

end
