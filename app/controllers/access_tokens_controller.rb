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

    @access_token.media_object_id = media_object_id if media_object_id
    @cancel_link = create_cancel_link(media_object_id)
  end

  def create
    @access_token = AccessToken.new(access_token_params)

    if @access_token.save
      redirect_to @access_token
    else
      @cancel_link = create_cancel_link(@access_token.media_object_id)
      render 'new', status: :unprocessable_entity
    end
  end

  def create_cancel_link(media_object_id)
    # Returns a link to the media object Access Control page, if a media
    # object id is given, otherwise returns a link to the Access Tokens list
    # page.
    return edit_media_object_path(id: media_object_id, step: 'access-control') if media_object_id.present?
    access_tokens_path
  end

  def show
    @access_token = AccessToken.find(params[:id])
    @media_object_access_control_link = edit_media_object_path(id: @access_token.media_object_id, step: 'access-control')
    media_object = MediaObject.find(@access_token.media_object_id)

    if (@access_token.active?)
      access_token_url = media_object_url(id: @access_token.media_object_id, access_token: @access_token.token)
      access_mode = t("access_token.access_mode.#{@access_token.access_mode}")
      expiration = @access_token.expiration.strftime("%B %e, %Y %I:%M:%S %p")

      @info_for_patron_snippet = t('access_token.info_for_patron_snippet_html',
                        access_token_url: access_token_url,
                        access_mode: access_mode,
                        media_object_title: media_object.title,
                        expiration: expiration)
    end
  end

  def edit
    @access_token = AccessToken.find(params[:id])
    @cancel_link = access_token_path(@access_token)
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
      tokens = AccessToken.with_status(status).order(:expiration)
      if cannot? :list_all, AccessToken
        # filter to only those tokens for which the current user is an editor
        # we cannot do this in the database only, so we have to paginate the array
        # instead of the ActiveRecord::Relation
        tokens = tokens.to_a.select {|token| current_ability.is_editor_of?(token.media_object.collection)}
        tokens = Kaminari.paginate_array(tokens)
      end
      tokens.page(params[:page])
    end

    def access_token_params
      data = params.require(:access_token).permit(%i[media_object_id access_mode expiration user revoked])
      begin
        data[:expiration] = Date.parse(data[:expiration]).in_time_zone(Rails.configuration.time_zone).end_of_day if data[:expiration]
      rescue StandardError => e
        # Simply recover and do nothing -- AccessToken validation should catch
        # missing parameter
      end
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
