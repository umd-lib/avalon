module AccessTokensHelper
  def css_classes(token)
    classes = []
    classes << 'expired' if token.expired?
    classes << 'revoked' if token.revoked?
    classes << 'active' if classes.empty?
    classes.map{|c| "token-#{c}"}.join(' ')
  end

  def status(token)
    return '⛔ Revoked' if token.revoked?
    return '⛔ Expired' if token.expired?

    '✅ Active'
  end

  def media_object_link(token)
    return "#{token.media_object_id} (Unknown media object ID)" unless token.media_object_exists?

    link_to MediaObject.find(token.media_object_id).title, media_object_url(token.media_object_id)
  end

  def media_object_with_token_link(token)
    if token.active?
      link_to token.token, media_object_url(id: token.media_object_id, access_token: token.token)
    else
      token.token
    end
  end

  def approximate_time_distance(token)
    distance_of_time_in_words_to_now(token.expiration) + ' ' + (token.expiration.past? ? 'ago' : 'from now')
  end

  def yes_no(boolean)
    boolean ? 'Yes' : 'No'
  end
end
