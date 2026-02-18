# Copyright 2011-2024, The Trustees of Indiana University and Northwestern
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

class CoursesController < ApplicationController
  before_action :authenticate_user!
  before_action :auth, except: [:stop_impersonating]

  def index
    @courses = courses_list
  end

  def export
    csv_data = CSV.generate(headers: true) do |csv|
      csv << ["id", "title", "context_id", "created_at"]
      Course.all.each do |course|
        csv << [course.id, course.title, course.context_id, course.created_at]
      end
    end
    respond_to do |format|
      format.csv { send_data csv_data, filename: "courses-#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv" }
    end
  end

  # Become a user
  def impersonate
    course_context_id = params[:id]
    user = User.find_by(email: course_context_id + '@' + ENV['SETTINGS__DOMAIN__HOST'])
    impersonate_user(user)
    user_session[:virtual_groups] = [course_context_id]
    user_session[:full_login] = false
    params['target_id'] = 'course_reserves'
    params['context_id'] = course_context_id
    redirect_to lti_redirect_url('lti', lti_group: course_context_id)
  end

  def stop_impersonating
    stop_impersonating_user
    user_session[:virtual_groups] = current_user.ldap_groups
    user_session.delete(:full_login)
    params.delete('target_id')
    params.delete('context_id')
    redirect_to courses_path, notice: t('samvera.persona.users.become.over')
  end

  private

    def auth
      current_ability.is_course_reserves_member? || current_ability.is_administrator?
    end

    def courses_list
      courses = Course.all.order(title: :asc)
      courses.page(params[:page])
    end
end