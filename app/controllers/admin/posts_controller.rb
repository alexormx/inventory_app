# frozen_string_literal: true

module Admin
  class PostsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :set_post, only: %i[edit update destroy publish unpublish]

    def index
      @status_filter = params[:status].presence_in(%w[draft published archived all]) || 'all'
      scope = Post.includes(:user).order(updated_at: :desc)
      scope = scope.where(status: @status_filter) unless @status_filter == 'all'
      @posts = scope.page(params[:page]).per(25)
      @counts = {
        draft: Post.draft.count,
        published: Post.published.count,
        archived: Post.archived.count,
        all: Post.count
      }
    end

    def new
      @post = Post.new
    end

    def create
      @post = Post.new(post_params)
      @post.user = current_user
      if @post.save
        redirect_to edit_admin_post_path(@post), notice: 'Borrador creado.'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @post.update(post_params)
        redirect_to edit_admin_post_path(@post), notice: 'Cambios guardados.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @post.destroy
      redirect_to admin_posts_path, notice: 'Publicación eliminada.'
    end

    def publish
      @post.update!(status: :published)
      redirect_back fallback_location: admin_posts_path, notice: 'Publicación en vivo.'
    end

    def unpublish
      @post.update!(status: :draft)
      redirect_back fallback_location: admin_posts_path, notice: 'Publicación regresada a borrador.'
    end

    private

    def set_post
      @post = Post.friendly.find(params[:id])
    end

    def post_params
      params.require(:post).permit(:title, :excerpt, :meta_description, :status, :editor_mode, :body, :body_html_raw, :cover_image)
    end
  end
end
