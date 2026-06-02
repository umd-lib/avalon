# Copyright 2011-2026, The Trustees of Indiana University and Northwestern
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

class DerivativesController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:authorize]

  # Validate if the session is active, the user is correct, and that they
  # have permission to stream the derivative based on the session_id and
  # the path to the stream.
  #
  # The values should be put into a POST. The method will reject a GET
  # request for security reasons
  def authorize
    resp = { authorized: StreamToken.validate_token(params[:token]) }
    if params[:name] and not resp[:authorized].any? { |valid| params[:name].index(valid).present? }
      return head :forbidden
    end

    # If the request header contains 'S3-Presigned-URL', we need to generate a presigned URL
    if request.headers['X-Want-S3-Presigned-URL'] == 'true'
      presigned_url = presigned_streaming_url(bucket:  Settings.encoding.derivative_bucket, key: params[:name], expires_in: 300)
      response.set_header('X-S3-Presigned-URL', presigned_url)
    end

    respond_to do |format|
      format.urlencoded do
        resp[:authorized] = resp[:authorized].join(';')
        render plain: resp.to_query, content_type: :urlencoded, status: :accepted
      end
      format.text do
        render plain: resp[:authorized].join("\n"), status: :accepted
      end
      format.xml do
        render xml: resp, root: :response, status: :accepted
      end
      format.json do
        render json: resp, status: :accepted
      end
    end
  rescue StreamToken::Unauthorized
    return head :forbidden
  end

  private

    def presigned_streaming_url(bucket:, key:, expires_in: 300)
      object = Aws::S3::Object.new(bucket_name: bucket, key: key)
      object.presigned_url(:get, expires_in: expires_in)
    end
end
