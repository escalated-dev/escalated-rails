module Escalated
  module Admin
    class CustomFieldsController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_field, only: [:update, :destroy]

      def index
        fields = Escalated::CustomField.ordered

        render inertia: "Escalated/Admin/CustomFields/Index", props: {
          fields: fields.map { |f| field_json(f) }
        }
      end

      def create
        field = Escalated::CustomField.new(field_params)

        if field.save
          redirect_to escalated.admin_custom_fields_path, notice: I18n.t('escalated.admin.custom_field.created')
        else
          redirect_back fallback_location: escalated.admin_custom_fields_path,
                        alert: field.errors.full_messages.join(", ")
        end
      end

      def update
        if @field.update(field_params)
          redirect_to escalated.admin_custom_fields_path, notice: I18n.t('escalated.admin.custom_field.updated')
        else
          redirect_back fallback_location: escalated.admin_custom_fields_path,
                        alert: @field.errors.full_messages.join(", ")
        end
      end

      def destroy
        @field.destroy!
        redirect_to escalated.admin_custom_fields_path, notice: I18n.t('escalated.admin.custom_field.deleted')
      end

      def reorder
        positions = params[:positions]

        return render json: { error: "positions required" }, status: :unprocessable_entity unless positions.is_a?(Array)

        positions.each_with_index do |field_id, index|
          Escalated::CustomField.where(id: field_id).update_all(position: index + 1)
        end

        render json: { success: true }
      end

      private

      def set_field
        @field = Escalated::CustomField.find(params[:id])
      end

      def field_params
        params.require(:custom_field).permit(
          :label, :key, :field_type, :applies_to, :position,
          :is_required, :is_agent_only, :description,
          options: []
        )
      end

      def field_json(field)
        {
          id: field.id,
          label: field.label,
          key: field.key,
          field_type: field.field_type,
          applies_to: field.applies_to,
          position: field.position,
          is_required: field.is_required,
          is_agent_only: field.is_agent_only,
          description: field.description,
          options: field.options,
          created_at: field.created_at&.iso8601,
          updated_at: field.updated_at&.iso8601
        }
      end
    end
  end
end
