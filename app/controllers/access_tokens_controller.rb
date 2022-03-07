class AccessTokensController < ApplicationController
  before_action :authenticate_user!

  STATUS_VALUES = %w[active expired revoked all]

  ACCESS_MODES = {
    'Streaming Only' => :streaming_only,
    'Download Only' => :download_only,
    'Streaming and Download' => :streaming_and_download,
  }

  def index
    @show_status = status_value
    @access_tokens = access_tokens_list(@show_status)
  end

  def new
    media_object_id = params[:media_object_id]
    @access_token ||= AccessToken.new(access_token_defaults)
    if media_object_id
      @access_token.media_object_id = media_object_id
      @cancel_link = edit_media_object_path(id: media_object_id)
    else
      @cancel_link = access_tokens_path
    end
  end

  def create
    @access_token = AccessToken.new(access_token_params)

    if @access_token.save
      redirect_to @access_token
    else
      render 'new', status: :unprocessable_entity
    end
  end

  def show
    @access_token = AccessToken.find(params[:id])
  end

  def edit
    @access_token = AccessToken.find(params[:id])
  end

  def update
    @access_token = AccessToken.find(params[:id])
    @access_token.update(access_token_params)
    if @access_token.save
      redirect_to @access_token
    else
      render 'edit', status: :unprocessable_entity
    end
  end

  def destroy

  end

  private

    # Get the value if the status query param. If none is given, or if it is not
    # one of the allowed values, returns 'active'.
    def status_value
      return 'active' if !params.include?(:status) || !STATUS_VALUES.include?(params[:status])

      params[:status]
    end

    def access_tokens_list(status)
      AccessToken.send(status).order(:expiration).page(params[:page])
    end

    def access_token_params
      data = params.require(:access_token).permit(%i[media_object_id access_mode expiration user revoked])
      data[:expiration] = Date.parse(data[:expiration]).in_time_zone(Rails.configuration.time_zone).end_of_day if data[:expiration]
      data[:user] = User.find_by_username_or_email(data[:user]) if data[:user]
      data.merge!(parse_access_mode(data.delete(:access_mode).to_sym)) if data[:access_mode]
      data
    end

    def parse_access_mode(access_mode)
      case access_mode
      when :streaming_only
        { allow_streaming: true, allow_download: false }
      when :download_only
        { allow_streaming: false, allow_download: true }
      when :streaming_and_download
        { allow_streaming: true, allow_download: true }
      else
        # default to no permissions
        { allow_streaming: false, allow_download: false }
      end
    end

    def access_token_defaults
      {
        user: current_user,
        expiration: 1.week.from_now
      }
    end
end
