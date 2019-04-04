# Copyright 2011-2018, The Trustees of Indiana University and Northwestern
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

# -*- encoding : utf-8 -*-
class Admin::UsersController < ApplicationController
  before_filter :auth, except: [:login_as]

  # TODO: finer controls
  def auth
    if current_user.nil?
      flash[:notice] = "You need to login to view users"
      redirect_to new_user_session_path
    elsif cannot? :read, User
      flash[:notice] = "You do not have permission to view users"
      redirect_to root_path
    end
  end

  def index
    @users = User.all
  end

  def login_as
    user = User.find(params[:user_id])
    if impersonating? && impersonating_admin_id == user.id
      sign_in(:user, user)
      session.delete(:admin_id)
    else
      if user && (can? :login_as, user)
        session[:admin_id] = current_user.id
        sign_in(:user, user)
      else
        flash[:notice] = "You do not have permission to access this page"
      end
    end
    redirect_to root_url # or user_root_url
  end
end
