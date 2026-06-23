# frozen_string_literal: true

require 'csv'

module Escalated
  module Admin
    class NewsletterListsController < Escalated::ApplicationController
      include Escalated::NewsletterAccess

      before_action :require_admin!
      before_action :ensure_newsletters_enabled!
      before_action -> { require_newsletter_permission!('newsletters.manage') }
      before_action :set_list, only: %i[show update destroy add_member remove_member import]

      def index
        lists = Escalated::NewsletterList
                .left_joins(:members)
                .select("#{Escalated::NewsletterList.table_name}.*, COUNT(#{Escalated::NewsletterListMember.table_name}.id) AS member_count") # rubocop:disable Layout/LineLength
                .group("#{Escalated::NewsletterList.table_name}.id")
                .map { |list| list_json(list) }

        render_page 'Escalated/Admin/Newsletters/Lists/Index', { lists: lists }
      end

      def show
        members = paginate(@list.members.includes(:contact).order(id: :desc), per_page: 100)
        match_count = if @list.kind == 'dynamic'
                        Escalated::Newsletter::ContactSegmentResolver.new.count_matches(@list.filter_json || { 'rules' => [] }) # rubocop:disable Layout/LineLength
                      else
                        0
                      end

        render_page 'Escalated/Admin/Newsletters/Lists/Show', {
          list: list_json(@list),
          members: members[:data],
          meta: members[:meta],
          matchCount: match_count
        }
      end

      def create
        render_page 'Escalated/Admin/Newsletters/Lists/Create', {}
      end

      def store
        data = list_params(require_kind: true)
        return unless data

        list = Escalated::NewsletterList.create!(data.merge(created_by: escalated_current_user&.id))
        redirect_to admin_newsletters_list_path(list)
      end

      def update
        data = list_params(require_kind: false)
        return unless data

        @list.update!(data.except(:kind))
        redirect_to admin_newsletters_list_path(@list)
      end

      def destroy
        @list.destroy!
        redirect_to admin_newsletters_lists_path
      end

      def add_member
        return unless static_list!

        contact_id = params[:contact_id]
        unless contact_id.present? && Escalated::Contact.exists?(contact_id)
          return render plain: 'contact_id is invalid', status: :unprocessable_content
        end

        Escalated::NewsletterListMember.find_or_create_by!(list_id: @list.id, contact_id: contact_id) do |member|
          member.added_by = escalated_current_user&.id
        end
        redirect_to admin_newsletters_list_path(@list)
      end

      def remove_member
        return unless static_list!

        Escalated::NewsletterListMember.where(list_id: @list.id, contact_id: params[:contact_id]).delete_all
        redirect_to admin_newsletters_list_path(@list)
      end

      def import
        return unless static_list!
        return render plain: 'file is required', status: :unprocessable_content unless params[:file].respond_to?(:path)

        imported = 0
        CSV.foreach(params[:file].path) do |row|
          email = row.first.to_s.strip
          next unless email.match?(URI::MailTo::EMAIL_REGEXP)

          contact = Escalated::Contact.find_or_create_by!(email: email)
          Escalated::NewsletterListMember.find_or_create_by!(list_id: @list.id, contact_id: contact.id) do |member|
            member.added_by = escalated_current_user&.id
          end
          imported += 1
        end

        redirect_to admin_newsletters_list_path(@list), notice: "Imported #{imported} contacts"
      end

      private

      def set_list
        @list = Escalated::NewsletterList.find(params[:id] || params[:list_id])
      end

      def list_params(require_kind:)
        data = params.permit(:name, :description, :kind, filter_json: {}).to_h.symbolize_keys
        errors = []
        errors << 'name is required' if require_kind && data[:name].blank?
        errors << 'name is too long' if data[:name].to_s.length > 255
        if require_kind
          errors << 'kind is invalid' unless %w[static dynamic].include?(data[:kind].to_s)
        elsif data.key?(:kind)
          data.delete(:kind)
        end
        return data if errors.empty?

        render plain: errors.join(', '), status: :unprocessable_content
        nil
      end

      def static_list!
        return true if @list.kind == 'static'

        render plain: 'Dynamic lists are filter-driven', status: :unprocessable_content
        false
      end

      def list_json(list)
        list.as_json.merge(
          'member_count' => list.respond_to?(:member_count) ? list.member_count.to_i : list.members.count,
          'opted_out_count' => opted_out_count(list)
        )
      end

      def opted_out_count(list)
        Escalated::NewsletterListMember
          .joins(:contact)
          .where(list_id: list.id)
          .where.not(Escalated::Contact.table_name => { marketing_opt_out_at: nil })
          .count
      end
    end
  end
end
