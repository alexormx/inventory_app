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
    count_view
    @related = Post.visible.where.not(id: @post.id).limit(3)
  end

  private

  # Incremento atómico que no toca updated_at (el índice admin ordena por él).
  # Se omiten admins y bots para que el contador refleje visitas reales.
  def count_view
    return if current_user&.admin?
    return if request.user_agent.to_s.match?(BOT_USER_AGENT_REGEX)

    Post.where(id: @post.id).update_all('views_count = views_count + 1')
  end
end
