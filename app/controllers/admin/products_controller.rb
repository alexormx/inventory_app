class Admin::ProductsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def index
    @products = Product.all
  end

  def show
    @product = Product.find(params[:id])
  end

  def new
    @product = Product.new
  end

  def edit
    @product = Product.find(params[:id])
  end
end
