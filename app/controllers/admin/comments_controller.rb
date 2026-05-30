# frozen_string_literal: true

module Admin
  class CommentsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :set_comment, only: %i[approve reject destroy]

    def index
      @status_filter = params[:status].presence_in(%w[pending approved rejected all]) || 'pending'

      scope = Comment.includes(:post, :user).order(created_at: :desc)
      scope = scope.where(status: @status_filter) unless @status_filter == 'all'

      @comments = scope.page(params[:page]).per(25)

      @counts = {
        pending: Comment.pending.count,
        approved: Comment.approved.count,
        rejected: Comment.rejected.count,
        all: Comment.count
      }
    end

    def approve
      @comment.update!(status: :approved)
      redirect_back fallback_location: admin_comments_path, notice: 'Comentario aprobado.'
    end

    def reject
      @comment.update!(status: :rejected)
      redirect_back fallback_location: admin_comments_path, notice: 'Comentario rechazado.'
    end

    def destroy
      @comment.destroy
      redirect_back fallback_location: admin_comments_path, notice: 'Comentario eliminado.'
    end

    private

    def set_comment
      @comment = Comment.find(params[:id])
    end
  end
end
