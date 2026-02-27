module Escalated
  module Admin
    class CustomObjectsController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_object_definition, only: [:update, :destroy, :records, :store_record, :update_record, :destroy_record]

      def index
        definitions = Escalated::CustomObject.ordered

        render inertia: "Escalated/Admin/CustomObjects/Index", props: {
          objects: definitions.map { |o| object_json(o) }
        }
      end

      def create
        definition = Escalated::CustomObject.new(object_params)

        if definition.save
          redirect_to escalated.admin_custom_objects_path, notice: I18n.t('escalated.admin.custom_object.created')
        else
          redirect_back fallback_location: escalated.admin_custom_objects_path,
                        alert: definition.errors.full_messages.join(", ")
        end
      end

      def update
        if @definition.update(object_params)
          redirect_to escalated.admin_custom_objects_path, notice: I18n.t('escalated.admin.custom_object.updated')
        else
          redirect_back fallback_location: escalated.admin_custom_objects_path,
                        alert: @definition.errors.full_messages.join(", ")
        end
      end

      def destroy
        @definition.destroy!
        redirect_to escalated.admin_custom_objects_path, notice: I18n.t('escalated.admin.custom_object.deleted')
      end

      def records
        result = paginate(@definition.records.recent)

        render json: {
          records: result[:data].map { |r| record_json(r) },
          meta: result[:meta]
        }
      end

      def store_record
        record = @definition.records.new(
          data: params[:data] || {},
          created_by: escalated_current_user.id
        )

        if record.save
          render json: record_json(record), status: :created
        else
          render json: { error: record.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      def update_record
        record = @definition.records.find(params[:record_id])

        if record.update(data: params[:data] || {})
          render json: record_json(record)
        else
          render json: { error: record.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      def destroy_record
        record = @definition.records.find(params[:record_id])
        record.destroy!

        render json: { success: true }
      end

      private

      def set_object_definition
        @definition = Escalated::CustomObject.find(params[:id])
      end

      def object_params
        params.require(:custom_object).permit(:name, :key, :description, fields: [:name, :type, :required])
      end

      def object_json(definition)
        {
          id: definition.id,
          name: definition.name,
          key: definition.key,
          description: definition.description,
          fields: definition.fields,
          record_count: definition.records.count,
          created_at: definition.created_at&.iso8601,
          updated_at: definition.updated_at&.iso8601
        }
      end

      def record_json(record)
        {
          id: record.id,
          data: record.data,
          created_at: record.created_at&.iso8601,
          updated_at: record.updated_at&.iso8601
        }
      end
    end
  end
end
