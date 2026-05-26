# frozen_string_literal: true

class PostsController < ApplicationController
  layout 'customer'

  def index
    @posts = Post.visible.page(params[:page]).per(10)
  end

  def show
    @post = Post.friendly.find(params[:id])
    unless @post.published? && @post.published_at && @post.published_at <= Time.current
      redirect_to blog_path, alert: 'Esta publicación no está disponible.'
      return
    end
    @related = Post.visible.where.not(id: @post.id).limit(3)
  end
end
