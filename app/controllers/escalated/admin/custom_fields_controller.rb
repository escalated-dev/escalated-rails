# frozen_string_literal: true

module Escalated
  module Admin
    class CustomFieldsController < Escalated::ApplicationController
      include Escalated::InertiaForms

      before_action :require_admin!
      before_action :set_field, only: %i[edit update destroy]

      def index
        fields = Escalated::CustomField.ordered

        render_page 'Escalated/Admin/CustomFields/Index', {
          fields: fields.map { |f| field_json(f) }
        }
      end

      def new
        render_page 'Escalated/Admin/CustomFields/Form', { field: nil, contexts: Escalated::CustomField::CONTEXTS }
      end

      def edit
        render_page 'Escalated/Admin/CustomFields/Form', {
          field: field_json(@field),
          contexts: Escalated::CustomField::CONTEXTS
        }
      end

      def create
        attributes = field_params
        errors = validate(attributes)
        return redirect_back_with_form_errors(errors, escalated.new_admin_custom_field_path) if errors.any?

        field = Escalated::CustomField.new(attributes)
        if field.save
          redirect_to escalated.admin_custom_fields_path, notice: I18n.t('escalated.admin.custom_field.created')
        else
          redirect_back_with_form_errors(record_errors(field), escalated.new_admin_custom_field_path)
        end
      end

      def update
        attributes = field_params
        errors = validate(attributes)
        return redirect_back_with_form_errors(errors, escalated.edit_admin_custom_field_path(@field)) if errors.any?

        if @field.update(attributes)
          redirect_to escalated.admin_custom_fields_path, notice: I18n.t('escalated.admin.custom_field.updated')
        else
          redirect_back_with_form_errors(record_errors(@field), escalated.edit_admin_custom_field_path(@field))
        end
      end

      def destroy
        @field.destroy!
        redirect_to escalated.admin_custom_fields_path, notice: I18n.t('escalated.admin.custom_field.deleted')
      end

      def reorder
        positions = params[:positions]

        unless positions.is_a?(Array)
          return render json: { error: 'positions required' },
                        status: :unprocessable_content
        end

        positions.each_with_index do |field_id, index|
          Escalated::CustomField.where(id: field_id).update_all(position: index + 1)
        end

        render json: { success: true }
      end

      private

      def set_field
        @field = Escalated::CustomField.find(params[:id])
      end

      # The body the shared form posts, as escalated-laravel reads it. The
      # column behind `type` is field_type.
      def field_params
        permitted = params.permit(:name, :type, :context, :required, :placeholder, :description, :position, :active,
                                  options: [], validation_rules: {}).to_h.symbolize_keys
        attributes = permitted.except(:type)
        attributes[:field_type] = permitted[:type] if permitted.key?(:type)
        %i[required active].each { |key| attributes[key] = boolean_param(attributes[key]) if attributes.key?(key) }
        attributes[:options] = Array(attributes[:options]) if attributes.key?(:options)
        attributes
      end

      def validate(attributes)
        errors = {}
        errors['name'] = 'The name field is required.' if attributes[:name].blank?
        unless Escalated::CustomField::FIELD_TYPES.include?(attributes[:field_type].to_s)
          errors['type'] = "The type must be one of: #{Escalated::CustomField::FIELD_TYPES.join(', ')}."
        end
        unless Escalated::CustomField::CONTEXTS.include?(attributes[:context].to_s)
          errors['context'] = "The context must be one of: #{Escalated::CustomField::CONTEXTS.join(', ')}."
        end
        errors
      end

      def field_json(field)
        {
          id: field.id,
          name: field.name,
          slug: field.slug,
          type: field.field_type,
          context: field.context,
          options: field.options || [],
          required: field.required,
          placeholder: field.placeholder,
          description: field.description,
          validation_rules: field.validation_rules,
          position: field.position,
          active: field.active,
          created_at: field.created_at&.iso8601,
          updated_at: field.updated_at&.iso8601
        }
      end
    end
  end
end
