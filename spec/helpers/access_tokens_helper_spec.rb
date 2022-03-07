require 'rails_helper'

# Specs in this file have access to a helper object that includes
# the AccessTokenHelper. For example:
#
# describe AccessTokenHelper do
#   describe 'string concat' do
#     it 'concats two strings with spaces' do
#       expect(helper.concat_strings('this','that')).to eq('this that')
#     end
#   end
# end
RSpec.describe AccessTokensHelper, type: :helper do
  active_token = AccessToken.new(expiration: 1.week.from_now, revoked: false)
  expired_token = AccessToken.new(expiration: 1.week.ago, revoked: false)
  revoked_token = AccessToken.new(expiration: 1.week.from_now, revoked: true)
  expired_and_revoked_token = AccessToken.new(expiration: 1.week.ago, revoked: true)

  describe 'yes_no' do
    it 'returns "Yes" for true' do
      expect(helper.yes_no(true)).to eq('Yes')
    end
    it 'returns "No" for false' do
      expect(helper.yes_no(false)).to eq('No')
    end
  end

  describe 'css_classes' do
    it 'returns token-expired for expired tokens' do
      expect(helper.css_classes(expired_token)).to eq('token-expired')
    end
    it 'returns token-revoked for revoked tokens' do
      expect(helper.css_classes(revoked_token)).to eq('token-revoked')
    end
    it 'returns token-active for active tokens' do
      expect(helper.css_classes(active_token)).to eq('token-active')
    end
    it 'returns "token-expired token-revoked" for expired and revoked tokens' do
      expect(helper.css_classes(expired_and_revoked_token)).to eq('token-expired token-revoked')
    end
  end

  describe 'status' do
    it 'returns Revoked for revoked tokens' do
      expect(helper.status(revoked_token)).to match(/Revoked/)
      expect(helper.status(expired_and_revoked_token)).to match(/Revoked/)
    end
    it 'returns Expired for expired (but not revoked) tokens' do
      expect(helper.status(expired_token)).to match(/Expired/)
    end
    it 'returns Active for active tokens' do
      expect(helper.status(active_token)).to match(/Active/)
    end
  end

  describe 'approximate_time_distance' do
    it 'returns "from now" for unexpired tokens' do
      expect(helper.approximate_time_distance(active_token)).to match('from now')
    end
    it 'returns "ago" for expired tokens' do
      expect(helper.approximate_time_distance(expired_token)).to match('ago')
    end
  end
end
