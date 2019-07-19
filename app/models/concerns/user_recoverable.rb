module UserRecoverable
  extend ActiveSupport::Concern

  # this can be overridden depending on what your using to store a user's
  # identity.
  def identity_attrs
    { email: email }
  end

  def recoverable?
    self.class.recoverable?(identity_attrs)
  end

  def omniauthable?
    self.class.omniauthable?
  end

  def identifiable?
    self.class.identifiable?
  end

  def find_identity_or_raise_error
    identity = Identity.locate(email: email)
    raise ActiveRecord::RecordNotFound unless identity
    identity
  end

  # Update password saving the record and clearing token. Returns true if
  # the passwords are valid and the record was saved, false otherwise.
  # https://github.com/plataformatec/devise/blob/master/lib/devise/models/recoverable.rb#L37-L55
  def reset_password(new_password, new_password_confirmation)
    super(new_password, new_password_confirmation) unless identifiable?
    raise NotImplementedError unless recoverable?

    identity = find_identity_or_raise_error
    if new_password.present?
      identity.password = new_password
      identity.password_confirmation = new_password_confirmation
      identity.save
    else
      errors.add(:password, :blank)
      false
    end
  end

  module ClassMethods
    def recoverable?(params)
      include?(Devise::Models::Recoverable) && Identity.exists?(params)
    end

    def omniauthable?
      include?(Devise::Models::Omniauthable) && !omniauth_providers.empty?
    end

    def identifiable?
      omniauthable? && omniauth_providers.include?(:identity)
    end

    def send_reset_password_instructions(attributes = {})
      recoverable = find_or_initialize_with_errors(reset_password_keys, attributes, :not_found)
      raise NotImplementedError unless recoverable.recoverable?
      recoverable.send_reset_password_instructions if recoverable.persisted?
      recoverable
    end
  end
end
