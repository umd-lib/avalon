if Settings.email.mailer.present? && Settings.email.mailer.intern == :aws_sdk
  require 'aws/rails/mailer'
  ActionMailer::Base.delivery_method = :aws_sdk
end
