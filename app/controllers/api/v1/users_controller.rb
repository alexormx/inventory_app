# frozen_string_literal: true

module Api
  module V1
    class UsersController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_with_token!

      # POST /api/v1/users
      # Crea usuarios (por defecto role=customer) permitiendo email y password opcionales para clientes offline
      def create
        attrs = user_params.to_h.symbolize_keys
        attrs[:role] = (attrs[:role].presence || 'customer').to_s
        # cast boolean created_offline; por defecto true si role=customer y no envían password
        attrs[:created_offline] = ActiveModel::Type::Boolean.new.cast(attrs[:created_offline])
        if attrs[:role] == 'customer' && attrs[:password].blank? && attrs[:password_confirmation].blank? && attrs[:created_offline].nil?
          attrs[:created_offline] = true
        end

        # Si no es customer y no mandan password, generamos uno aleatorio
        if attrs[:role] != 'customer' && attrs[:password].blank?
          gen = SecureRandom.hex(8)
          attrs[:password] = gen
          attrs[:password_confirmation] = gen
        end

        @user = User.new(attrs)
        # No enviar correo de confirmación (Devise Confirmable)
        @user.skip_confirmation!

        if @user.save
          render json: { message: 'User created', id: @user.id, email: @user.email, role: @user.role }, status: :created
        else
          render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/users/exists?email=...&phone=...
      def exists
        email = params[:email].to_s.strip
        phone = params[:phone].to_s.strip
        exists = false
        exists ||= User.exists?(['LOWER(email) = ?', email.downcase]) if email.present?
        exists ||= User.exists?(phone: phone) if phone.present?
        render json: { exists: exists }, status: :ok
      end

      private

      def user_params
        params.expect(
          user: %i[name
                   email
                   phone
                   role
                   discount_rate
                   created_offline
                   password
                   password_confirmation]
        )
      end
    end
  end
end
