class DeviseMailerPreview < ActionMailer::Preview
  def confirmation_instructions
    user = User.new(email: "ejemplo@email.com", confirmation_token: "123abc")
    Devise::Mailer.confirmation_instructions(user, user.confirmation_token)
  end

  def reset_password_instructions
    user = User.new(email: "recuperar@email.com")
    token = "reset123"
    Devise::Mailer.reset_password_instructions(user, token)
  end
  
  def unlock_instructions
    user = User.new(email: "bloqueado@email.com")
    token = "unlock456"  # simulamos un token
    Devise::Mailer.unlock_instructions(user, token)
  end

  def email_changed
    user = User.new(email: "nuevo@email.com")
    Devise::Mailer.email_changed(user)
  end

  def password_change
    user = User.new(email: "usuario@email.com")
    Devise::Mailer.password_change(user)
  end
end