class CleanupAccessTokenJob < ActiveJob::Base
  def perform
    unexpired_tokens = AccessToken.where(expired: false)
    unexpired_tokens.each do |access_token|
      access_token.expire if access_token.expired?
    end
  end
end
