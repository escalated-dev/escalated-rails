module Escalated
  module Admin
    class MacrosController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_macro, only: [:update, :destroy]

      def index
        macros = Escalated::Macro.ordered

        render inertia: "Escalated/Admin/Macros/Index", props: {
          macros: macros.map { |m| macro_json(m) }
        }
      end

      def create
        macro = Escalated::Macro.new(macro_params)
        macro.created_by = escalated_current_user.id

        if macro.save
          redirect_to admin_macros_path, notice: I18n.t('escalated.admin.macro.created')
        else
          redirect_back fallback_location: admin_macros_path,
                        alert: macro.errors.full_messages.join(", ")
        end
      end

      def update
        if @macro.update(macro_params)
          redirect_to admin_macros_path, notice: I18n.t('escalated.admin.macro.updated')
        else
          redirect_back fallback_location: admin_macros_path,
                        alert: @macro.errors.full_messages.join(", ")
        end
      end

      def destroy
        @macro.destroy!
        redirect_to admin_macros_path, notice: I18n.t('escalated.admin.macro.deleted')
      end

      private

      def set_macro
        @macro = Escalated::Macro.find(params[:id])
      end

      def macro_params
        params.require(:macro).permit(:name, :description, :is_shared, :order, actions: [:type, :value])
      end

      def macro_json(macro)
        {
          id: macro.id,
          name: macro.name,
          description: macro.description,
          actions: macro.actions,
          is_shared: macro.is_shared,
          order: macro.order,
          creator: macro.creator ? {
            id: macro.creator.id,
            name: macro.creator.respond_to?(:name) ? macro.creator.name : macro.creator.email
          } : nil,
          created_at: macro.created_at&.iso8601,
          updated_at: macro.updated_at&.iso8601
        }
      end

      def admin_macros_path
        escalated.admin_macros_path
      end
    end
  end
end
