# frozen_string_literal: true

class CommentsController < ApplicationController
  layout 'customer'
  before_action :authenticate_user!
  before_action :set_post

  def create
    comment = @post.comments.build(comment_params)
    comment.user = current_user
    comment.status = :pending

    if comment.save
      redirect_to post_path(@post, anchor: 'comentarios'),
                  notice: 'Tu comentario fue enviado y está pendiente de moderación. ¡Gracias!'
    else
      redirect_to post_path(@post, anchor: 'comentarios'),
                  alert: "No se pudo guardar tu comentario: #{comment.errors.full_messages.to_sentence}"
    end
  end

  private

  def set_post
    @post = Post.friendly.find(params[:post_id])
    return if @post.published? && @post.published_at && @post.published_at <= Time.current

    redirect_to blog_path, alert: 'Esta publicación no está disponible.'
  end

  def comment_params
    params.require(:comment).permit(:body)
  end
end
