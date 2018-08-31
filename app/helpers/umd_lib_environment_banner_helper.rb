module UMDLibEnvironmentBannerHelper
  # https://confluence.umd.edu/display/LIB/Create+Environment+Banners
  def umd_lib_environment_banner
    if environment
      content_tag :div, "#{environment} Environment",
        class: 'environment-banner',
        id: "environment-#{environment.downcase}"
    end
  end

  # When the banner is visible, add the extra-padding-top class
  # to increase body padding
  def extra_padding_top 
    if environment
      return 'extra-padding-top'
    end
  end

  # Returns 'Local', 'Development', 'Staging', or nil (indicating a production
  # server), depending on the server environment.
  #
  # The "ENVIRONMENT_BANNER" environment variable can optionally be used to
  # force a particular environment setting. Use "Production" to
  # indicate a production system on non-production servers.
  def environment
    # Allow override using "ENVIRONMENT_BANNER" environment variable.
    env_var = ENV['ENVIRONMENT_BANNER']
    return nil if !env_var.nil? && env_var.downcase == 'production'
    return env_var if !env_var.blank?
    
    return 'Local' if Rails.env.development?
    
    hostname = `hostname -s`
    return 'Development' if hostname =~ /dev$/
    return 'Staging' if hostname =~ /stage$/
    
    # Otherwise return nil, indicating production
  end

end
