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

class Ability
  # include CanCan::Ability
  include Hydra::Ability
  include Hydra::MultiplePolicyAwareAbility

  self.ability_logic += [:playlist_permissions,
                         :playlist_item_permissions,
                         :marker_permissions,
                         :encode_dashboard_permissions,
                         :timeline_permissions,
                         :checkout_permissions]

  # Override to add handling of SpeedyAF proxy objects
  def edit_permissions
    super

    can [:edit, :update, :destroy], SpeedyAF::Base do |obj|
      test_edit(obj.id)
    end
  end

  def read_permissions
    super

    can :read, SpeedyAF::Base do |obj|
      test_read(obj.id)
    end
  end

  def encode_dashboard_permissions
    can :read, :encode_dashboard if is_administrator?
  end

  # UMD Customization
  def self.access_token_download_group_name(media_object_id)
    # Returns the group name to use if downloads are allowed for a media object
    # via an access token
    "allow_download_#{media_object_id}"
  end
  # End UMD Customization

  def user_groups
    return @user_groups if @user_groups

    @user_groups = default_user_groups
    @user_groups |= current_user.groups if current_user and current_user.respond_to? :groups
    @user_groups |= ['registered'] unless current_user.new_record?
    @user_groups |= @options[:virtual_groups] if @options.present? and @options.has_key? :virtual_groups
    # UMD Customization
    if @options.present? and @options.has_key? :remote_ip
      remote_ip = @options[:remote_ip]
      @user_groups |= [remote_ip]
      umd_ip_manager_groups = UmdIpManager.new.groups(ip_address: remote_ip)
      @user_groups |= umd_ip_manager_groups.map { |g| g.prefixed_key }
    end

    if @options.present? && @options.has_key?(:access_token)
      token = @options[:access_token]
      @user_groups |= access_token_user_groups(token)
    end
    # End UMD Customization
    @user_groups
  end

  # UMD Customization
  def access_token_user_groups(token)
    # Returns a list of the user groups based on the token, or an empty list.
    return [] if token.nil?

    access_token = AccessToken.find_by(token: token)
    return [] unless !access_token.nil? && access_token.active? && access_token.allow_download?

    media_object_id = access_token.media_object_id
    [Ability.access_token_download_group_name(media_object_id)]
  end
  # End UMD Customization

  def create_permissions(user=nil, session=nil)
    if full_login? || is_api_request?
      if is_administrator?
        can :manage, :all
      end

      if @user_groups.include? "group_manager"
        can :manage, Admin::Group do |group|
           group.nil? or !['administrator','group_manager'].include?(group.name)
        end
      end

      if is_member_of_any_collection?
        can :create, MediaObject
      end

      if @user_groups.include? "manager"
        can :create, Admin::Collection
      end
    end
  end

  def custom_permissions(user=nil, session=nil)

    unless (full_login? || is_api_request?) and is_administrator?
      # UMD Customization
      # Begin customization for LIBAVALON-168
      can :read, [MediaObject, SpeedyAF::Proxy::MediaObject] do |media_object|
        media_object.published? || test_edit(media_object.id)
      end

      # For media playback
      can :full_read, [MediaObject, SpeedyAF::Proxy::MediaObject] do |media_object|
        (test_read(media_object.id) && media_object.published?) || test_edit(media_object.id)
      end

      can :stream, [MediaObject, SpeedyAF::Proxy::MediaObject] do |media_object|
        is_streaming_allowed?(media_object)
      end

      can :read, [MasterFile, SpeedyAF::Proxy::MasterFile] do |master_file|
        can? :full_read, master_file.media_object
      end

      can :minimal_read, [MasterFile, SpeedyAF::Proxy::MasterFile] do |master_file|
        can? :read, master_file.media_object
      end

      can :read, [Derivative, SpeedyAF::Proxy::Derivative] do |derivative|
        can? :full_read, derivative.masterfile.media_object
      end
      # End UMD Customization for LIBAVALON-168

      # UMD Customization for LIBAVALON-196
      can :master_file_download, [MasterFile, SpeedyAF::Proxy::MasterFile] do |master_file|
        is_master_file_download_allowed?(master_file)
      end

      # End UMD Customization for LIBAVALON-196

      # UMD Customization
      can [:create, :update], AccessToken do |access_token|
        is_member_of?(access_token.media_object.collection)
      end

      can :list_all, AccessToken if is_administrator?

      can :manage, AccessToken if (is_member_of_any_collection? or @user_groups.include? 'manager')
      # End UMD Customization

      cannot :read, [Admin::Collection, SpeedyAF::Proxy::Admin::Collection] unless (full_login? || is_api_request?)

      if full_login? || is_api_request?
        can [:read, :items], [Admin::Collection, SpeedyAF::Proxy::Admin::Collection] do |collection|
          is_member_of?(collection)
        end

        unless (is_member_of_any_collection? or @user_groups.include? 'manager')
          cannot :read, [Admin::Collection, SpeedyAF::Proxy::Admin::Collection]
        end

        can :update_access_control, [MediaObject, SpeedyAF::Proxy::MediaObject] do |media_object|
          # UMD Customization
          @user.in?(media_object.collection.managers) || is_editor_of?(media_object.collection)
          # End UMD Customization
        end

        can :unpublish, [MediaObject, SpeedyAF::Proxy::MediaObject] do |media_object|
          @user.in?(media_object.collection.managers)
        end

        can :update, [Admin::Collection, SpeedyAF::Proxy::Admin::Collection] do |collection|
          is_editor_of?(collection)
        end

        can :update_unit, [Admin::Collection, SpeedyAF::Proxy::Admin::Collection] do |collection|
          @user.in?(collection.managers)
        end

        can :update_access_control, [Admin::Collection, SpeedyAF::Proxy::Admin::Collection] do |collection|
          @user.in?(collection.managers)
        end

        can :update_managers, [Admin::Collection, SpeedyAF::Proxy::Admin::Collection] do |collection|
          @user.in?(collection.managers)
        end

        can :update_editors, [Admin::Collection, SpeedyAF::Proxy::Admin::Collection] do |collection|
          @user.in?(collection.managers)
        end

        can :update_depositors, [Admin::Collection, SpeedyAF::Proxy::Admin::Collection] do |collection|
          is_editor_of?(collection)
        end

        can :destroy, ::Admin::CollectionPresenter do |collection|
          @user.in?(collection.managers)
        end

        can :inspect, [MediaObject, SpeedyAF::Proxy::MediaObject] do |media_object|
          is_member_of?(media_object.collection)
        end

        can :show_progress, [MediaObject, SpeedyAF::Proxy::MediaObject] do |media_object|
          is_member_of?(media_object.collection)
        end

        can [:edit, :destroy, :update], [MasterFile, SpeedyAF::Proxy::MasterFile] do |master_file|
          can? :edit, master_file.media_object
        end

        can :download, [MasterFile, SpeedyAF::Proxy::MasterFile] do |master_file|
          @user.in?(master_file.media_object.collection.managers)
        end

        # Users logged in through LTI cannot share
        can :share, [MediaObject, SpeedyAF::Proxy::MediaObject]
      end

      # if is_api_request?
      #   can :manage, MediaObject
      #   can :manage, Admin::Collection
      #   can :manage, Avalon::ControlledVocabulary
      # end

      cannot :update, [MediaObject, SpeedyAF::Proxy::MediaObject] do |media_object|
        (not (full_login? || is_api_request?)) || (!is_member_of?(media_object.collection)) ||
          # UMD Customization
          ( media_object.published? && !(@user.in?(media_object.collection.managers) || @user.in?(media_object.collection.editors)) )
          # End UMD Customization
      end

      cannot :destroy, [MediaObject, SpeedyAF::Proxy::MediaObject] do |media_object|
        # non-managers can only destroy media_object if it's unpublished
        (not (full_login? || is_api_request?)) || (!is_member_of?(media_object.collection)) ||
          ( media_object.published? && !@user.in?(media_object.collection.managers) )
      end

      cannot :destroy, [Admin::Collection, SpeedyAF::Proxy::Admin::Collection] do |collection, other_user_collections=[]|
        (not (full_login? || is_api_request?)) || !@user.in?(collection.managers)
      end

      can :intercom_push, [MediaObject, SpeedyAF::Proxy::MediaObject] do |media_object|
        # anyone who can edit a media_object can also push it
        can? :edit, media_object
      end

      can :json_update, [MediaObject, SpeedyAF::Proxy::MediaObject] do |media_object|
        # anyone who can edit a media_object can also update it via the API
        is_api_request? && can?(:edit, media_object)
      end
    end
  end

  def playlist_permissions
    if @user.id.present?
      can :manage, Playlist, user: @user
      # can :create, Playlist
      can :duplicate, Playlist, visibility: Playlist::PUBLIC
      can :duplicate, Playlist do |playlist|
        playlist.valid_token?(@options[:playlist_token])
      end
    end
    can :read, Playlist, visibility: Playlist::PUBLIC
    can :read, Playlist do |playlist|
      playlist.valid_token?(@options[:playlist_token])
    end
  end

  def playlist_item_permissions
    if @user.id.present?
      can [:create, :update, :delete], PlaylistItem do |playlist_item|
        can? :manage, playlist_item.playlist
      end
    end
    can :read, PlaylistItem do |playlist_item|
      (can? :read, playlist_item.playlist) &&
      (can? :read, playlist_item.master_file)
    end
  end

  def marker_permissions
    if @user.id.present?
      can [:create, :update, :delete], AvalonMarker do |marker|
        can? :manage, marker.playlist_item.playlist
      end
    end
    can :read, AvalonMarker do |marker|
      (can? :read, marker.playlist_item.playlist) &&
      (can? :read, marker.playlist_item.master_file)
    end
  end

  def timeline_permissions
    if @user.id.present?
      can :manage, Timeline, user: @user
      can :duplicate, Timeline, visibility: Timeline::PUBLIC
      can :duplicate, Timeline do |timeline|
        timeline.valid_token?(@options[:timeline_token])
      end
    end
    can :read, Timeline, visibility: Timeline::PUBLIC
    can :read, Timeline do |timeline|
      timeline.valid_token?(@options[:timeline_token])
    end
  end

  def checkout_permissions
    if @user.id.present?
      can :create, Checkout do |checkout|
        checkout.user == @user && can?(:read, checkout.media_object)
      end
      can :return, Checkout, user: @user
      can :return_all, Checkout, user: @user
      can :read, Checkout, user: @user
      can :update, Checkout, user: @user
      can :destroy, Checkout, user: @user
    end
  end

  def is_administrator?
    @user_groups.include?("administrator")
  end

  def is_member_of?(collection)
     is_administrator? ||
       @user.in?(collection.managers, collection.editors, collection.depositors)
  end

  # UMD Customization
  def is_master_file_download_allowed?(master_file)
    # Returns true if download of the master file is allowed, false otherwise
    media_object = master_file&.media_object
    return false unless media_object

    media_object_id = media_object.id

    collection = media_object.collection
    return false unless collection

    allowed = is_member_of?(collection)
    allowed = allowed || @user_groups.include?(Ability.access_token_download_group_name(media_object_id))
    allowed
  end

  def is_streaming_allowed?(media_object)
    # Returns true if streaming of the given media object is allowed,
    # false otherwise
    return false unless media_object

    allowed = can? :full_read, media_object

    if @options.has_key?(:access_token)
      token = @options[:access_token]
      # access token should only override other permissions for published objects
      allowed = allowed || (media_object.published? && AccessToken.allow_streaming_of?(token, media_object.id))
    end

    allowed
  end
  # End UMD Customization

  def is_editor_of?(collection)
     is_administrator? ||
       @user.in?(collection.editors_and_managers)
  end

  def is_member_of_any_collection?
    @user.id.present? && Admin::Collection.exists?("inheritable_edit_access_person_ssim" => @user.user_key)
  end

  def full_login?
    return @full_login unless @full_login.nil?
    @full_login = ( @options.present? and @options.has_key? :full_login ) ? @options[:full_login] : true
    @full_login
  end

  def is_api_request?
    @json_api_login ||= !!@options[:json_api_login] if @options.present?
    @json_api_login ||= false
    @json_api_login
  end

end
