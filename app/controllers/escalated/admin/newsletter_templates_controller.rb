# frozen_string_literal: true

module Escalated
  module Admin
    class NewsletterTemplatesController < Escalated::ApplicationController
      include Escalated::NewsletterAccess

      before_action :require_admin!
      before_action :ensure_newsletters_enabled!
      before_action -> { require_newsletter_permission!('newsletters.manage') }
      before_action :set_template, only: %i[show update destroy]

      def index
        render_page 'Escalated/Admin/Newsletters/Templates/Index', {
          templates: Escalated::NewsletterTemplate.order(created_at: :desc)
        }
      end

      def show
        render_page 'Escalated/Admin/Newsletters/Templates/Show', {
          template: @template,
          themes: themes,
          isNew: false
        }
      end

      def create
        render_page 'Escalated/Admin/Newsletters/Templates/Create', { themes: themes }
      end

      def store
        data = template_params
        return unless data

        Escalated::NewsletterTemplate.create!(data.merge(created_by: escalated_current_user&.id))
        redirect_to admin_newsletters_templates_path
      end

      def update
        data = template_params
        return unless data

        @template.update!(data)
        redirect_to admin_newsletters_template_path(@template)
      end

      def destroy
        @template.destroy!
        redirect_to admin_newsletters_templates_path
      end

      private

      def set_template
        @template = Escalated::NewsletterTemplate.find(params[:id])
      end

      def template_params
        data = params.permit(:name, :theme, :subject_template, :body_markdown,
                             merge_fields_schema: {}).to_h.symbolize_keys
        errors = []
        errors << 'name is required' if data[:name].blank?
        errors << 'name is too long' if data[:name].to_s.length > 255
        errors << 'theme is required' if data[:theme].blank?
        errors << 'theme is too long' if data[:theme].to_s.length > 64
        errors << 'subject_template is too long' if data[:subject_template].to_s.length > 998
        errors << 'body_markdown is required' if data[:body_markdown].blank?
        return data if errors.empty?

        render plain: errors.join(', '), status: :unprocessable_content
        nil
      end

      def themes
        roots = [
          Escalated.configuration.newsletter_themes_dir,
          File.expand_path('../../../views/escalated/newsletter_themes', __dir__)
        ].compact
        found = roots.flat_map do |root|
          next [] unless File.directory?(root)

          Dir[File.join(root, '*.html.erb')].map { |path| File.basename(path, '.html.erb') }
        end.uniq
        found.presence || %w[default branded]
      end
    end
  end
end
