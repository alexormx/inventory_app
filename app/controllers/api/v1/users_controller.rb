class Api::V1::UsersController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_with_token!

  # POST /api/v1/users
  # Crea usuarios (por defecto role=customer) permitiendo email y password opcionales para clientes offline
  def create
    attrs = user_params.to_h.symbolize_keys
    attrs[:role] = (attrs[:role].presence || "customer").to_s
    # cast boolean created_offline
    attrs[:created_offline] = ActiveModel::Type::Boolean.new.cast(attrs[:created_offline])

    # Si no es customer y no mandan password, generamos uno aleatorio
    if attrs[:role] != "customer" && attrs[:password].blank?
      gen = SecureRandom.hex(8)
      attrs[:password] = gen
      attrs[:password_confirmation] = gen
    end

    @user = User.new(attrs)
    # No enviar correo de confirmación (Devise Confirmable)
    @user.skip_confirmation!

    if @user.save
      render json: { message: "User created", id: @user.id, email: @user.email, role: @user.role }, status: :created
    else
      render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/users/exists?email=...&phone=...
  def exists
    email = params[:email].to_s.strip
    phone = params[:phone].to_s.strip
    exists = false
    if email.present?
      exists ||= User.where("LOWER(email) = ?", email.downcase).exists?
    end
    if phone.present?
      exists ||= User.where(phone: phone).exists?
    end
    render json: { exists: exists }, status: :ok
  end

  private

  def authenticate_with_token!
    token = request.headers["Authorization"].to_s.split(" ").last
    user = User.find_by(api_token: token)

    if user&.admin?
      @current_user = user
    else
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end

  def user_params
    params.require(:user).permit(
      :name,
      :email,
      :phone,
      :role,
      :discount_rate,
      :created_offline,
      :password,
      :password_confirmation
    )
  end
end
