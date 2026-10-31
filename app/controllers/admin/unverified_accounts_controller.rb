# frozen_string_literal: true

module Admin
  # Cuentas que el cliente creó en el registro público y no han confirmado su
  # correo. Las de más de User::UNVERIFIED_REVIEW_AFTER quedan "En revisión":
  # el admin decide si reenviar el correo, verificarla a mano o eliminarla.
  # Las creadas por admin o API no aparecen (se confirman al crearse).
  class UnverifiedAccountsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :set_user, only: %i[resend_confirmation confirm]

    PER_PAGE = 50

    def index
      scope = User.unverified_self_registered
      @review_count = User.unverified_needing_review.count
      @waiting_count = scope.count - @review_count
      @users = scope.order(:created_at).page(params[:page]).per(PER_PAGE)
      ids = @users.map(&:id)
      @favorites = Favorite.open.where(user_id: ids).group(:user_id).count
      @last_visits = VisitorLog.where(user_id: ids).group(:user_id).maximum(:last_visited_at)
    end

    def resend_confirmation
      @user.send_confirmation_instructions
      redirect_back_or_to admin_unverified_accounts_path,
                          notice: "Se reenvió el correo de confirmación a #{@user.email}."
    end

    def confirm
      if @user.confirm
        expire_sidebar_badges
        redirect_back_or_to admin_unverified_accounts_path, notice: "La cuenta de #{@user.email} quedó verificada."
      else
        redirect_back_or_to admin_unverified_accounts_path,
                            alert: "No se pudo verificar: #{@user.errors.full_messages.to_sentence}"
      end
    end

    private

    # Solo cuentas pendientes: así estas acciones no tocan clientes ya
    # verificados ni cuentas creadas por el admin.
    def set_user
      @user = User.unverified_self_registered.find(params[:id])
    end

    def expire_sidebar_badges
      Rails.cache.delete('admin/sidebar_badges')
    end
  end
end
