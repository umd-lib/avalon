# frozen_string_literal: true

class Users::PasswordsController < Devise::PasswordsController
  helper_method :new_session_path
  rescue_from NotImplementedError, with: :unrecoverable

  protected

    def after_sign_in_path_for(resource_or_scope)
      signed_in_root_path(resource_or_scope)
    end

    # some Devise views call new_session_path('user'). This just returns the new
    # user session path.
    def new_session_path(_resource_name)
      new_user_session_path
    end

    def unrecoverable
      flash[:error] = "Sorry, but it is not possible to reset your password on your account. Please contact you system administrator." 
      redirect_to new_user_session_path
    end

end
