class AccessToken < ApplicationRecord
  belongs_to :user

  after_initialize :generate_token
  after_initialize :set_defaults

  validate :media_object_must_exist

  before_save :set_expired_flag
  after_create :add_read_group

  # Generates a URL-safe base64 encoded 12 byte token.
  def generate_token
    self.token ||= Base64.urlsafe_encode64(SecureRandom.random_bytes(12))
  end

  # Sets some (fairly restrictive) defaults for this token.
  def set_defaults
    self.allow_download ||= false
    self.allow_streaming ||= false
    self.expired ||= false
    self.revoked ||= false
  end

  # Checks whether the expiration time for this token is in the past.
  def should_expire?
    self.expiration.past?
  end

  # Sets the #expired attribute based on whether this token should expire.
  def set_expired_flag
    self.expired = should_expire?
  end

  # Checks whether the target media object exists
  def media_object_exists?
    MediaObject.exists? self.media_object_id
  end

  # Validation method to check whether the target media object exists
  def media_object_must_exist
    errors.add(:media_object, 'does not exist') unless media_object_exists?
  end

  # Adds read group to the media_object, using the token as the group identifier
  def add_read_group
    media_object = MediaObject.find(self.media_object_id)
    media_object.read_groups += [self.token]
    media_object.save!
  end
end
