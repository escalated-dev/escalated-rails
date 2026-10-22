# frozen_string_literal: true

module Escalated
  module Admin
    class CustomObjectsController < Escalated::ApplicationController
      include Escalated::InertiaForms

      FIELD_TYPES = %w[text number select date lookup].freeze

      before_action :require_admin!
      before_action :set_object_definition,
                    only: %i[edit update destroy records store_record update_record destroy_record]

      def index
        definitions = Escalated::CustomObject.order(:name)
        counts = Escalated::CustomObjectRecord.where(object_id: definitions.map(&:id)).group(:object_id).count

        render_page 'Escalated/Admin/CustomObjects/Index', {
          objects: definitions.map { |o| object_json(o).merge(records_count: counts.fetch(o.id, 0)) }
        }
      end

      def new
        render_page 'Escalated/Admin/CustomObjects/Form', { object: nil }
      end

      def edit
        render_page 'Escalated/Admin/CustomObjects/Form', { object: object_json(@definition) }
      end

      def create
        attributes = object_params
        errors = validate(attributes, nil)
        return redirect_back_with_form_errors(errors, escalated.new_admin_custom_object_path) if errors.any?

        definition = Escalated::CustomObject.new(attributes)
        if definition.save
          redirect_to escalated.admin_custom_objects_path, notice: I18n.t('escalated.admin.custom_object.created')
        else
          redirect_back_with_form_errors(record_errors(definition), escalated.new_admin_custom_object_path)
        end
      end

      def update
        attributes = object_params
        errors = validate(attributes, @definition)
        if errors.any?
          return redirect_back_with_form_errors(errors, escalated.edit_admin_custom_object_path(@definition))
        end

        if @definition.update(attributes)
          redirect_to escalated.admin_custom_objects_path, notice: I18n.t('escalated.admin.custom_object.updated')
        else
          redirect_back_with_form_errors(record_errors(@definition),
                                         escalated.edit_admin_custom_object_path(@definition))
        end
      end

      def destroy
        @definition.destroy!
        redirect_to escalated.admin_custom_objects_path, notice: I18n.t('escalated.admin.custom_object.deleted')
      end

      # The Records page in a browser; the paginated list as JSON to a JSON
      # request, which is what this action answered before the page existed.
      def records
        if request.format.json? && !inertia_request?
          result = paginate(@definition.records.order(id: :desc))
          return render json: { records: result[:data].map { |r| record_json(r) }, meta: result[:meta] }
        end

        render_page 'Escalated/Admin/CustomObjects/Records', {
          object: object_json(@definition),
          records: @definition.records.order(id: :desc).map { |r| record_json(r) }
        }
      end

      def store_record
        record = @definition.records.new(data: record_data)

        if record.save
          record_done(:record_created) { render json: record_json(record), status: :created }
        else
          record_failed(record)
        end
      end

      def update_record
        record = @definition.records.find(params[:record_id])

        if record.update(data: record_data)
          record_done(:record_updated) { render json: record_json(record) }
        else
          record_failed(record)
        end
      end

      def destroy_record
        record = @definition.records.find(params[:record_id])
        record.destroy!

        record_done(:record_deleted) { render json: { success: true } }
      end

      private

      def set_object_definition
        @definition = Escalated::CustomObject.find(params[:id])
      end

      def records_path
        escalated.records_admin_custom_object_path(@definition)
      end

      # Back to the Records page for the page's Inertia visit; the JSON answer
      # (the block) for any other caller.
      def record_done(message)
        return yield unless inertia_request?

        redirect_back_or_to(records_path, notice: I18n.t("escalated.admin.custom_object.#{message}"))
      end

      def record_failed(record)
        return redirect_back_with_form_errors(record_errors(record), records_path) if inertia_request?

        render json: { error: record.errors.full_messages.join(', ') }, status: :unprocessable_content
      end

      def record_data
        data = params[:data]
        data.is_a?(ActionController::Parameters) ? data.permit!.to_h : {}
      end

      # The body the shared form posts, as escalated-laravel reads it.
      def object_params
        attributes = params.permit(:name, :slug).to_h.symbolize_keys
        if params.key?(:fields_schema)
          attributes[:fields_schema] = Array(params[:fields_schema]).map do |field|
            next {} unless field.respond_to?(:permit)

            field = field.permit(:name, :type, :required, options: []).to_h
            field['required'] = boolean_param(field['required']) if field.key?('required')
            field
          end
        end
        attributes
      end

      # The rules escalated-laravel's CustomObjectController validates with.
      def validate(attributes, existing)
        errors = {}
        errors['name'] = 'The name field is required.' if attributes[:name].blank?

        slug = attributes[:slug].to_s
        if slug.blank? || slug !~ /\A[A-Za-z0-9_-]{1,100}\z/
          errors['slug'] = 'The slug may only contain letters, numbers, dashes and underscores.'
        elsif Escalated::CustomObject.where(slug: slug).where.not(id: existing&.id).exists?
          errors['slug'] = 'The slug has already been taken.'
        end

        schema = attributes[:fields_schema]
        if !schema.is_a?(Array) || schema.empty?
          errors['fields_schema'] = 'At least one field is required.'
        else
          schema.each_with_index do |field, index|
            errors["fields_schema.#{index}.name"] = 'The field name is required.' if field['name'].blank?
            unless FIELD_TYPES.include?(field['type'].to_s)
              errors["fields_schema.#{index}.type"] = "The field type must be one of: #{FIELD_TYPES.join(', ')}."
            end
          end
        end
        errors
      end

      def object_json(definition)
        {
          id: definition.id,
          name: definition.name,
          slug: definition.slug,
          fields_schema: definition.fields_schema || [],
          created_at: definition.created_at&.iso8601,
          updated_at: definition.updated_at&.iso8601
        }
      end

      def record_json(record)
        {
          id: record.id,
          object_id: record[:object_id],
          data: record.data,
          created_at: record.created_at&.iso8601,
          updated_at: record.updated_at&.iso8601
        }
      end
    end
  end
end
