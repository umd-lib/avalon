# Copyright 2011-2023, The Trustees of Indiana University and Northwestern
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


module Avalon
  module Authentication
    def self.lti_configured?
      Devise.omniauth_providers.include?(:lti)
    end

    def self.load_configs
      configs = Settings&.auth&.configuration
      if configs.blank?
        []
      elsif configs.is_a?(Array)
        configs.collect(&:to_hash)
      else
        configs.to_hash.values
      end
    end

    Config = load_configs
    if ENV['LTI_AUTH_KEY']
      Config << { name: 'LTI', provider: :lti, hidden: true, params: { oauth_credentials: { ENV['LTI_AUTH_KEY'] => ENV['LTI_AUTH_SECRET'] } } }
    end

    # UMD Customization
    saml_config = Config.find { |conf| conf[:provider] == :saml }
    if saml_config
      saml_config[:params][:issuer] = ENV['SAML_ISSUER'] if ENV['SAML_ISSUER']
      saml_config[:params][:assertion_consumer_service_url] = URI::join(Settings.domain, "/users/auth/saml/callback").to_s
      saml_config[:params][:private_key] = ENV['SAML_SP_PRIVATE_KEY'] if ENV['SAML_SP_PRIVATE_KEY']
      saml_config[:params][:certificate] = ENV['SAML_SP_CERTIFICATE'] if ENV['SAML_SP_CERTIFICATE']
    end
    # End UMD Customization

    Providers = Config.reject {|provider| provider[:provider].blank? }
    VisibleProviders = Providers.reject {|provider| provider[:hidden]}
    HiddenProviders = Providers - VisibleProviders
  end
end
