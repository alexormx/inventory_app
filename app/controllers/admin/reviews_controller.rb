# frozen_string_literal: true

module Admin
  class ReviewsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :set_review, only: %i[approve reject destroy]

    def index
      @status_filter = params[:status].presence_in(%w[pending approved rejected all]) || 'pending'

      scope = Review.includes(:product, :user).order(created_at: :desc)
      scope = scope.where(status: @status_filter) unless @status_filter == 'all'

      @reviews = scope.page(params[:page]).per(25)

      @counts = {
        pending: Review.pending.count,
        approved: Review.approved.count,
        rejected: Review.rejected.count,
        all: Review.count
      }
    end

    def approve
      @review.update!(status: :approved)
      redirect_back fallback_location: admin_reviews_path, notice: 'Reseña aprobada.'
    end

    def reject
      @review.update!(status: :rejected)
      redirect_back fallback_location: admin_reviews_path, notice: 'Reseña rechazada.'
    end

    def destroy
      @review.destroy
      redirect_back fallback_location: admin_reviews_path, notice: 'Reseña eliminada.'
    end

    private

    def set_review
      @review = Review.find(params[:id])
    end
  end
end
