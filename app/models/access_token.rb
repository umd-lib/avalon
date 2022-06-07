class AccessToken < ApplicationRecord
  belongs_to :user

  after_initialize :generate_token
  after_initialize :set_defaults

  validates :media_object_id, presence: true
  validate :media_object_must_exist
  validates :expiration, presence: true
  validate :expiration_must_be_future
  validate :user_must_be_collection_member

  after_create :add_read_group

  scope :expired, ->{ where('expiration <= NOW()')}
  scope :revoked, ->{ where(revoked: true) }
  scope :active, ->{ where('expiration > NOW() AND NOT revoked')}
  scope :with_status, ->(status) { send(status) }

  # Convenience method for accessing instance version of "allow_streaming_of?"
  # with just a token string and media object id
  def self.allow_streaming_of?(token, media_object_id)
    access_token = AccessToken.find_by(token: token)
    return false if access_token.nil?

    access_token.allow_streaming_of?(media_object_id)
  end

  # Returns true if streaming is allowed by this access token for the given
  # media object id, false otherwise.
  def allow_streaming_of?(media_object_id)
    allow_streaming? && active? && self.media_object_id == media_object_id
  end

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

  # Returns true if this token has not expired and not revoked, false
  # otherwise.
  def active?
    !expired? && !revoked?
  end

  # Returns true if the expiration time for this token is in the past, or the
  # "expired" field is true, false otherwise.
  def expired?
    self.expiration.past? || self[:expired]
  end

  # Sets the expiration date. Overridden to only allow the expiration date
  # on new, unsaved records to be set.
  def expiration=(expiration_date)
    unless self.new_record?
      logger.warn("Attempted to set expiration on existing record: access_token id=#{self.id}. Update ignored")
      return
    end
    super(expiration_date)

    self.expired = expiration_date.nil? || (expiration_date == '') || expiration_date.past?
  end

  # Expires this access token if the expiration date is passed
  def expire
    return unless expired?

    self.expired = true
    # Skip validation, because otherwise we will fail
    # "expiration_must_be_future" validation check
    self.save(validate: false) unless self.new_record?
    remove_read_group
  end

  # Checks whether the target media object exists
  def media_object_exists?
    MediaObject.exists? self.media_object_id
  end

  # Validation method to check whether the expiration is in the future
  def expiration_must_be_future
    return if expiration.nil?
    errors.add(:expiration, 'is in the past') unless expiration.future?
  end

  # Validation method to check whether the target media object exists
  def media_object_must_exist
    if media_object_id.present?
      errors.add(:media_object_id, 'not found') unless media_object_exists?
    end
  end

  # Validation method to check whether the user creating this token is an admin
  # or "member" (manager, editor, or depositor) of the collection holding the
  # media object. If this validation fails, it sets a "not found" error, even
  # though the media object does exist. This is to prevent leaking information
  # about what media objects exist to an unauthorized user.
  def user_must_be_collection_member
    if media_object_id.present? && media_object_exists?
      errors.add(:media_object_id, 'not found') unless Ability.new(user).is_member_of?(media_object.collection)
    end
  end

  # Adds read group to the media_object, using the token as the group identifier
  def add_read_group
    return if expired?

    unless media_object.read_groups.include?(self.token)
      media_object.read_groups += [self.token]
      media_object.save!
    end
  end

  # Removes the read group added by this token from the media_object
  def remove_read_group
    if media_object && media_object.read_groups.include?(self.token)
      media_object.read_groups -= [self.token]
      media_object.save!
    end
  end

  def access_mode
    if allow_streaming? && allow_download?
      :streaming_and_download
    elsif allow_streaming?
      :streaming_only
    elsif allow_download?
      :download_only
    end
  end

  def media_object_id=(media_object_id)
    # Reset @media_object whenever media_object_id is changed
    @media_object = nil
    super(media_object_id)
  end

  def media_object
    @media_object ||= MediaObject.find(self.media_object_id)
  end
end
