Permalink.on_generate do |object,target|
  if object.is_a? MediaObject
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
  else
    return nil
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
