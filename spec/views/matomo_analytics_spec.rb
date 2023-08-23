# This is a UMD-added file
require 'rails_helper'

describe "modules/_matomo_analytics.html.erb", type: :view do
  context "Matomo Analytics environment variables are configured" do
    before do
      ENV['MATOMO_ANALYTICS_URL'] = 'https://test.example.cloud/'
      ENV['MATOMO_ANALYTICS_SITE_ID'] = '14'
      ENV['MATOMO_ANALYTICS_CDN_SRC'] = '//test.example.cloud/umd.matomo.cloud/matomo.js'
    end

    it 'has Matomo script when all environment variables are configured' do
      render
      expect(has_matomo_script?).to be true
    end

    it 'does not have Matomo script if "MATOMO_ANALYTICS_URL" enviroment variable is not configured' do
      ENV['MATOMO_ANALYTICS_URL'] = nil
      render
      expect(has_matomo_script?).to be false
    end

    it 'does not have Matomo script if "MATOMO_ANALYTICS_SITE_ID" enviroment variable is not configured' do
      ENV['MATOMO_ANALYTICS_SITE_ID'] = ''
      render
      expect(has_matomo_script?).to be false
    end

    it 'does not have Matomo script if "MATOMO_ANALYTICS_CDN_SRC" enviroment variable is not configured' do
      ENV.delete('MATOMO_ANALYTICS_CDN_SRC')
      render
      expect(has_matomo_script?).to be false
    end
  end

  # Returns true if the Matomo script is present in the "rendered" string,
  # false otherwise.
  def has_matomo_script?
    rendered.include?('var _paq = window._paq = window._paq || [];')
  end
end
