# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: 'soporte@pasatiempos.com.mx'
  layout 'mailer'
end
