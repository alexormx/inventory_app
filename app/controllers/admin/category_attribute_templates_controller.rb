# frozen_string_literal: true

module Admin
  class CategoryAttributeTemplatesController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :set_template, only: [:edit, :update, :destroy]

    # GET /admin/category_attribute_templates
    def index
      @templates = CategoryAttributeTemplate.order(:category)
      @categories_without_template = Product.distinct.pluck(:category).map(&:downcase).uniq -
                                     CategoryAttributeTemplate.pluck(:category)
    end

    # GET /admin/category_attribute_templates/new
    def new
      @template = CategoryAttributeTemplate.new(
        category: params[:category],
        attributes_schema: default_schema
      )
    end

    # POST /admin/category_attribute_templates
    def create
      @template = CategoryAttributeTemplate.new(template_params)

      if @template.save
        redirect_to admin_category_attribute_templates_path,
                    notice: "Template para '#{@template.category}' creado."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # GET /admin/category_attribute_templates/:id/edit
    def edit; end

    # PATCH /admin/category_attribute_templates/:id
    def update
      if @template.update(template_params)
        redirect_to admin_category_attribute_templates_path,
                    notice: "Template para '#{@template.category}' actualizado."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /admin/category_attribute_templates/:id
    def destroy
      @template.destroy
      redirect_to admin_category_attribute_templates_path,
                  notice: "Template eliminado."
    end

    private

    def set_template
      @template = CategoryAttributeTemplate.find(params[:id])
    end

    def template_params
      permitted = params.require(:category_attribute_template).permit(:category, :active, attributes_schema: {})
      # The schema comes as JSON string from the form
      if params[:category_attribute_template][:attributes_schema_json].present?
        permitted[:attributes_schema] = JSON.parse(params[:category_attribute_template][:attributes_schema_json])
      end
      permitted
    rescue JSON::ParserError
      permitted
    end

    def default_schema
      [
        { "key" => "", "label" => "", "type" => "string", "required" => false, "position" => 1, "example" => "" }
      ]
    end
  end
end
