# frozen_string_literal: true

require 'rails_helper'

# The admin config screens the shared frontend drives for statuses, roles,
# business hours, custom fields and custom objects: their lists, their Form
# pages (src/pages/Admin/*/Form.vue), the custom object Records page, and the
# bodies those pages post. Props and bodies follow escalated-laravel's
# controllers, which the shared pages were written against.
RSpec.describe 'Admin config forms', type: :request do
  let(:admin) { create(:user, :admin, email: 'admin-config-forms@example.test') }

  before do
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(admin)
  end

  describe 'statuses' do
    let(:body) do
      { label: 'Waiting on vendor', category: 'pending', color: '#123456',
        description: 'Parked until the vendor answers.', position: 3, is_default: true }
    end

    it 'lists statuses with the fields the list reads' do
      status = create(:escalated_ticket_status, label: 'Triage', category: 'open')

      page = expect_screen('/support/admin/statuses', 'Escalated/Admin/Statuses/Index')

      expect(page.dig('props', 'categories')).to eq(%w[new open pending on_hold solved])
      expect(page.dig('props', 'statuses').sole).to include(
        'id' => status.id, 'label' => 'Triage', 'category' => 'open', 'color' => status.color,
        'position' => status.position, 'is_default' => false
      )
    end

    it 'renders the empty form' do
      page = expect_screen('/support/admin/statuses/new', 'Escalated/Admin/Statuses/Form')

      expect(page.dig('props', 'status')).to be_nil
      expect(page.dig('props', 'categories')).to eq(%w[new open pending on_hold solved])
    end

    it 'renders the form for an existing status' do
      status = create(:escalated_ticket_status, label: 'Triage', category: 'open', description: 'First look')

      page = expect_screen("/support/admin/statuses/#{status.id}/edit", 'Escalated/Admin/Statuses/Form')

      expect(page.dig('props', 'status')).to include(
        'id' => status.id, 'label' => 'Triage', 'category' => 'open', 'color' => status.color,
        'description' => 'First look', 'position' => status.position, 'is_default' => false
      )
    end

    it 'creates a status from the body the form posts and keeps one default per category' do
      old_default = create(:escalated_ticket_status, category: 'pending', is_default: true)

      expect { inertia_visit(:post, '/support/admin/statuses', body) }
        .to change(Escalated::TicketStatus, :count).by(1)

      expect(response).to redirect_to('/support/admin/statuses')
      expect(Escalated::TicketStatus.find_by(label: 'Waiting on vendor')).to have_attributes(
        category: 'pending', color: '#123456', description: 'Parked until the vendor answers.',
        position: 3, is_default: true
      )
      expect(old_default.reload.is_default).to be(false)
    end

    it 'updates a status' do
      status = create(:escalated_ticket_status, category: 'open')

      inertia_visit(:put, "/support/admin/statuses/#{status.id}", body.merge(is_default: false))

      expect(response).to redirect_to('/support/admin/statuses')
      expect(status.reload).to have_attributes(label: 'Waiting on vendor', category: 'pending',
                                               description: 'Parked until the vendor answers.')
    end

    it 'sends a refused save back to the form with the errors on their fields' do
      inertia_visit(:post, '/support/admin/statuses', body.merge(label: '', category: 'nonsense'),
                    referer: '/support/admin/statuses/new')

      expect(response).to redirect_to('/support/admin/statuses/new')
      expect(Escalated::TicketStatus.count).to eq(0)
      expect(session[:inertia_errors]&.keys).to include('label', 'category')
    end
  end

  describe 'roles' do
    # The roles screens exist only while roles & permissions is on (ADR
    # 2026-10-29); the admin then needs role permissions of their own.
    before do
      Escalated.configuration.access = { roles_permissions: true }
      allow(Escalated::AccessControl).to receive(:permission_slugs).and_return(%w[role.view role.manage])
    end

    after { Escalated.configuration.access = {} }

    let!(:view_tickets) { create(:escalated_permission, name: 'View tickets', slug: 'tickets.view', group: 'Tickets') }
    let!(:edit_settings) do
      create(:escalated_permission, name: 'Edit settings', slug: 'settings.edit', group: 'Settings')
    end

    it 'lists roles with their user counts' do
      role = create(:escalated_role, name: 'Supervisor', description: 'Leads a team')
      role.users << admin

      page = expect_screen('/support/admin/roles', 'Escalated/Admin/Roles/Index')

      expect(page.dig('props', 'roles').sole).to include(
        'id' => role.id, 'name' => 'Supervisor', 'description' => 'Leads a team', 'is_system' => false,
        'users_count' => 1
      )
    end

    it 'renders the empty form with the permissions grouped as the matrix reads them' do
      page = expect_screen('/support/admin/roles/new', 'Escalated/Admin/Roles/Form')

      expect(page.dig('props', 'role')).to be_nil
      grouped = page.dig('props', 'permissions')
      expect(grouped.keys).to contain_exactly('Tickets', 'Settings')
      expect(grouped['Tickets'].sole).to include('id' => view_tickets.id, 'slug' => 'tickets.view',
                                                 'name' => 'View tickets', 'group' => 'Tickets')
    end

    it 'renders the form for an existing role with its permissions' do
      role = create(:escalated_role, name: 'Supervisor')
      role.permissions << view_tickets

      page = expect_screen("/support/admin/roles/#{role.id}/edit", 'Escalated/Admin/Roles/Form')

      expect(page.dig('props', 'role')).to include('id' => role.id, 'name' => 'Supervisor')
      expect(page.dig('props', 'role', 'permissions').pluck('id')).to eq([view_tickets.id])
      expect(page.dig('props', 'permissions', 'Settings').sole['id']).to eq(edit_settings.id)
    end

    it 'creates a role with the permission ids the form posts' do
      expect do
        inertia_visit(:post, '/support/admin/roles',
                      { name: 'Supervisor', description: 'Leads a team', permissions: [view_tickets.id] })
      end.to change(Escalated::Role, :count).by(1)

      expect(response).to redirect_to('/support/admin/roles')
      role = Escalated::Role.find_by(name: 'Supervisor')
      expect(role.description).to eq('Leads a team')
      expect(role.permissions).to contain_exactly(view_tickets)
    end

    it 'updates a role and syncs its permissions, clearing them when none are sent' do
      role = create(:escalated_role, name: 'Supervisor')
      role.permissions << view_tickets

      inertia_visit(:put, "/support/admin/roles/#{role.id}",
                    { name: 'Lead', description: nil, permissions: [edit_settings.id] })
      expect(response).to redirect_to('/support/admin/roles')
      expect(role.reload.name).to eq('Lead')
      expect(role.permissions).to contain_exactly(edit_settings)

      inertia_visit(:put, "/support/admin/roles/#{role.id}", { name: 'Lead', permissions: [] })
      expect(role.reload.permissions).to be_empty
    end
  end

  describe 'business hours' do
    let(:week) do
      {
        'monday' => { 'start' => '08:00', 'end' => '16:00' },
        'tuesday' => { 'start' => '08:00', 'end' => '16:00' },
        'wednesday' => { 'start' => '', 'end' => '' }
      }
    end
    let(:body) do
      { name: 'Support desk', timezone: 'America/Toronto', is_default: true, schedule: week,
        holidays: [{ name: 'Canada Day', date: '2026-07-01', recurring: true }] }
    end

    it 'lists schedules with their holidays' do
      schedule = create(:escalated_business_schedule, name: 'Support desk', is_default: true)
      create(:escalated_holiday, schedule: schedule, name: 'Canada Day', date: Date.new(2026, 7, 1), recurring: true)

      page = expect_screen('/support/admin/business_hours', 'Escalated/Admin/BusinessHours/Index')

      row = page.dig('props', 'schedules').sole
      expect(row).to include('id' => schedule.id, 'name' => 'Support desk', 'timezone' => 'UTC', 'is_default' => true)
      expect(row['holidays'].sole).to include('name' => 'Canada Day', 'date' => '2026-07-01', 'recurring' => true)
    end

    it 'renders the empty form with the timezones to choose from' do
      page = expect_screen('/support/admin/business_hours/new', 'Escalated/Admin/BusinessHours/Form')

      expect(page.dig('props', 'schedule')).to be_nil
      expect(page.dig('props', 'timezones')).to include('UTC', 'America/Toronto', 'Europe/London')
    end

    it 'renders the form for an existing schedule' do
      schedule = create(:escalated_business_schedule, name: 'Support desk')
      create(:escalated_holiday, schedule: schedule, name: 'Canada Day', date: Date.new(2026, 7, 1))

      page = expect_screen("/support/admin/business_hours/#{schedule.id}/edit", 'Escalated/Admin/BusinessHours/Form')

      expect(page.dig('props', 'schedule')).to include('id' => schedule.id, 'name' => 'Support desk',
                                                       'is_default' => false)
      expect(page.dig('props', 'schedule', 'schedule', 'monday')).to include('start' => '09:00', 'end' => '17:00')
      expect(page.dig('props', 'schedule', 'holidays').sole).to include('name' => 'Canada Day', 'date' => '2026-07-01')
    end

    it 'creates a schedule with its holidays and keeps one default' do
      old_default = create(:escalated_business_schedule, is_default: true)

      expect { inertia_visit(:post, '/support/admin/business_hours', body) }
        .to change(Escalated::BusinessSchedule, :count).by(1)

      expect(response).to redirect_to('/support/admin/business_hours')
      schedule = Escalated::BusinessSchedule.find_by(name: 'Support desk')
      expect(schedule).to have_attributes(timezone: 'America/Toronto', is_default: true)
      expect(schedule.schedule).to eq(week)
      expect(schedule.holidays.sole).to have_attributes(name: 'Canada Day', date: Date.new(2026, 7, 1), recurring: true)
      expect(old_default.reload.is_default).to be(false)
    end

    it 'updates a schedule and replaces its holidays' do
      schedule = create(:escalated_business_schedule, :with_holidays)

      inertia_visit(:put, "/support/admin/business_hours/#{schedule.id}", body.merge(is_default: false))

      expect(response).to redirect_to('/support/admin/business_hours')
      expect(schedule.reload).to have_attributes(name: 'Support desk', timezone: 'America/Toronto')
      expect(schedule.holidays.map(&:name)).to eq(['Canada Day'])
    end

    it 'refuses a timezone that does not exist' do
      inertia_visit(:post, '/support/admin/business_hours', body.merge(timezone: 'Mars/Olympus_Mons'),
                    referer: '/support/admin/business_hours/new')

      expect(response).to redirect_to('/support/admin/business_hours/new')
      expect(Escalated::BusinessSchedule.count).to eq(0)
    end
  end

  describe 'custom fields' do
    let(:body) do
      { name: 'Plan tier', type: 'select', context: 'ticket', options: %w[Free Pro], required: true,
        placeholder: 'Pick one', description: 'The plan on the account', position: 4, active: true }
    end

    it 'lists fields with the names the list reads' do
      field = create(:escalated_custom_field, :select, name: 'Plan tier', position: 2)

      page = expect_screen('/support/admin/custom_fields', 'Escalated/Admin/CustomFields/Index')

      expect(page.dig('props', 'fields').sole).to include(
        'id' => field.id, 'name' => 'Plan tier', 'type' => 'select', 'context' => 'ticket',
        'required' => false, 'position' => 2
      )
    end

    it 'renders the empty form' do
      page = expect_screen('/support/admin/custom_fields/new', 'Escalated/Admin/CustomFields/Form')

      expect(page.dig('props', 'field')).to be_nil
      expect(page.dig('props', 'contexts')).to eq(%w[ticket user organization])
    end

    it 'renders the form for an existing field' do
      field = create(:escalated_custom_field, :select, name: 'Plan tier', placeholder: 'Pick one')

      page = expect_screen("/support/admin/custom_fields/#{field.id}/edit", 'Escalated/Admin/CustomFields/Form')

      expect(page.dig('props', 'field')).to include(
        'id' => field.id, 'name' => 'Plan tier', 'type' => 'select', 'context' => 'ticket',
        'options' => ['Option A', 'Option B', 'Option C'], 'required' => false, 'placeholder' => 'Pick one',
        'description' => field.description, 'position' => field.position, 'active' => true
      )
    end

    it 'creates a field from the body the form posts' do
      expect { inertia_visit(:post, '/support/admin/custom_fields', body) }
        .to change(Escalated::CustomField, :count).by(1)

      expect(response).to redirect_to('/support/admin/custom_fields')
      expect(Escalated::CustomField.last).to have_attributes(
        name: 'Plan tier', field_type: 'select', context: 'ticket', options: %w[Free Pro], required: true,
        placeholder: 'Pick one', description: 'The plan on the account', position: 4, active: true
      )
    end

    it 'updates a field' do
      field = create(:escalated_custom_field)

      inertia_visit(:put, "/support/admin/custom_fields/#{field.id}", body.merge(active: false, context: 'user'))

      expect(response).to redirect_to('/support/admin/custom_fields')
      expect(field.reload).to have_attributes(name: 'Plan tier', field_type: 'select', context: 'user', active: false)
    end

    it 'refuses a type the form does not offer' do
      inertia_visit(:post, '/support/admin/custom_fields', body.merge(type: 'hologram'),
                    referer: '/support/admin/custom_fields/new')

      expect(response).to redirect_to('/support/admin/custom_fields/new')
      expect(Escalated::CustomField.count).to eq(0)
    end
  end

  describe 'custom objects' do
    let(:schema) do
      [{ 'name' => 'serial', 'type' => 'text', 'required' => true, 'options' => [] },
       { 'name' => 'tier', 'type' => 'select', 'required' => false, 'options' => %w[gold silver] }]
    end
    let(:body) { { name: 'Device', slug: 'device', fields_schema: schema } }

    it 'lists objects with their record counts' do
      object = create(:escalated_custom_object, :with_records, name: 'Device', slug: 'device')

      page = expect_screen('/support/admin/custom_objects', 'Escalated/Admin/CustomObjects/Index')

      expect(page.dig('props', 'objects').sole).to include(
        'id' => object.id, 'name' => 'Device', 'slug' => 'device', 'records_count' => 3,
        'fields_schema' => object.fields_schema
      )
    end

    it 'renders the empty form' do
      page = expect_screen('/support/admin/custom_objects/new', 'Escalated/Admin/CustomObjects/Form')

      expect(page.dig('props', 'object')).to be_nil
    end

    it 'renders the form for an existing object' do
      object = create(:escalated_custom_object, name: 'Device', slug: 'device')

      page = expect_screen("/support/admin/custom_objects/#{object.id}/edit", 'Escalated/Admin/CustomObjects/Form')

      expect(page.dig('props', 'object')).to include('id' => object.id, 'name' => 'Device', 'slug' => 'device',
                                                     'fields_schema' => object.fields_schema)
    end

    it 'creates an object from the body the form posts' do
      expect { inertia_visit(:post, '/support/admin/custom_objects', body) }
        .to change(Escalated::CustomObject, :count).by(1)

      expect(response).to redirect_to('/support/admin/custom_objects')
      expect(Escalated::CustomObject.last).to have_attributes(name: 'Device', slug: 'device', fields_schema: schema)
    end

    it 'updates an object' do
      object = create(:escalated_custom_object)

      inertia_visit(:put, "/support/admin/custom_objects/#{object.id}", body)

      expect(response).to redirect_to('/support/admin/custom_objects')
      expect(object.reload).to have_attributes(name: 'Device', slug: 'device', fields_schema: schema)
    end

    it 'refuses an object with no fields or a slug already taken' do
      create(:escalated_custom_object, slug: 'device')

      inertia_visit(:post, '/support/admin/custom_objects', body, referer: '/support/admin/custom_objects/new')
      expect(response).to redirect_to('/support/admin/custom_objects/new')

      inertia_visit(:post, '/support/admin/custom_objects', body.merge(slug: 'gadget', fields_schema: []),
                    referer: '/support/admin/custom_objects/new')
      expect(response).to redirect_to('/support/admin/custom_objects/new')

      expect(Escalated::CustomObject.count).to eq(1)
    end

    describe 'records' do
      let(:object) { create(:escalated_custom_object, name: 'Device', slug: 'device', fields_schema: schema) }

      it 'renders the records page, newest first' do
        older = create(:escalated_custom_object_record, object: object, data: { 'serial' => 'A-1' })
        newer = create(:escalated_custom_object_record, object: object, data: { 'serial' => 'B-2' })

        page = expect_screen("/support/admin/custom_objects/#{object.id}/records",
                             'Escalated/Admin/CustomObjects/Records')

        expect(page.dig('props', 'object')).to include('id' => object.id, 'name' => 'Device',
                                                       'fields_schema' => schema)
        expect(page.dig('props', 'records').pluck('id')).to eq([newer.id, older.id])
        expect(page.dig('props', 'records', 0, 'data')).to eq('serial' => 'B-2')
      end

      it 'still answers JSON to a JSON request' do
        create(:escalated_custom_object_record, object: object, data: { 'serial' => 'A-1' })

        get "/support/admin/custom_objects/#{object.id}/records", as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['records'].sole['data']).to eq('serial' => 'A-1')
      end

      it 'adds, edits and deletes records from the page and goes back to it' do
        records_path = "/support/admin/custom_objects/#{object.id}/records"

        expect do
          inertia_visit(:post, records_path, { data: { serial: 'C-3', tier: 'gold' } }, referer: records_path)
        end.to change(object.records, :count).by(1)
        expect(response).to redirect_to(records_path)

        record = object.records.sole
        expect(record.data).to eq('serial' => 'C-3', 'tier' => 'gold')

        inertia_visit(:put, "#{records_path}/#{record.id}", { data: { serial: 'C-4' } }, referer: records_path)
        expect(response).to redirect_to(records_path)
        expect(record.reload.data).to eq('serial' => 'C-4')

        inertia_visit(:delete, "#{records_path}/#{record.id}", nil, referer: records_path)
        expect(response).to redirect_to(records_path)
        expect(object.records.count).to eq(0)
      end
    end
  end
end
