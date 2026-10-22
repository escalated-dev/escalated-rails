# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

# Admin/Settings/DatabaseConnection: which database Escalated's tables live
# on. In this engine that is `config.database_connection` (or the host's
# primary connection), read once when the models load, so the screen is the
# read-only form of Laravel's: it shows every configured connection and
# probes them, and refuses to switch.
RSpec.describe 'Admin database connection settings', type: :request do
  let(:admin) { create(:user, :admin, email: 'admin-database@example.test') }
  let(:primary) { ActiveRecord::Base.connection_db_config }

  before do
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(admin)
  end

  # A second connection in database.yml, pointing at a database that exists
  # but has never had the migrations run.
  def with_archive_connection
    Dir.mktmpdir do |dir|
      archive = ActiveRecord::DatabaseConfigurations::HashConfig.new(
        Rails.env, 'archive', { adapter: 'sqlite3', database: File.join(dir, 'archive.sqlite3') }
      )
      allow(ActiveRecord::Base.configurations).to receive(:configs_for)
        .with(env_name: Rails.env).and_return([primary, archive])

      yield
    end
  end

  it 'shows the connection in use and probes every configured one' do
    create(:escalated_ticket)

    with_archive_connection do
      page = expect_screen('/support/admin/settings/database', 'Escalated/Admin/Settings/DatabaseConnection')
      props = page['props']

      expect(props).to include('current' => nil, 'hostDefault' => primary.name, 'pinnedByConfig' => true,
                               'tablePrefix' => 'escalated_')
      expect(props['connections'].pluck('name')).to eq([primary.name, 'archive'].sort)

      in_use = props['connections'].find { |c| c['name'] == primary.name }
      expect(in_use).to include('is_current' => true, 'is_host_default' => true, 'reachable' => true,
                                'migrated' => true, 'ticket_count' => 1, 'error' => nil,
                                'driver' => primary.adapter)

      archive = props['connections'].find { |c| c['name'] == 'archive' }
      expect(archive).to include('is_current' => false, 'is_host_default' => false, 'reachable' => true,
                                 'migrated' => false, 'ticket_count' => nil, 'driver' => 'sqlite3',
                                 'database' => 'archive.sqlite3')
    end
  end

  it 'names the configured connection as current when one is set' do
    allow(Escalated.configuration).to receive(:database_connection).and_return(primary.name.to_sym)

    get '/support/admin/settings/database'

    expect(inertia_page.dig('props', 'current')).to eq(primary.name)
  end

  it 'reports a probe of one connection back to the screen' do
    with_archive_connection do
      inertia_visit(:post, '/support/admin/settings/database/test', { connection: 'archive' },
                    referer: '/support/admin/settings/database')

      expect(response).to redirect_to('/support/admin/settings/database')
      expect(flash[:alert]).to include('archive', 'no Escalated tables')

      inertia_visit(:post, '/support/admin/settings/database/test', { connection: primary.name },
                    referer: '/support/admin/settings/database')

      expect(flash[:notice]).to include(primary.name, 'ready')
    end
  end

  it 'refuses to probe a connection that is not configured' do
    inertia_visit(:post, '/support/admin/settings/database/test', { connection: 'nowhere' },
                  referer: '/support/admin/settings/database')

    expect(response).to redirect_to('/support/admin/settings/database')
    expect(session[:inertia_errors]).to include('connection')
  end

  it 'refuses to switch, because the connection is set in configuration' do
    inertia_visit(:post, '/support/admin/settings/database', { connection: 'archive' },
                  referer: '/support/admin/settings/database')

    expect(response).to redirect_to('/support/admin/settings/database')
    expect(flash[:alert]).to include('config.database_connection')
  end

  it 'is for admins only' do
    allow_any_instance_of(Escalated::ApplicationController) # rubocop:disable RSpec/AnyInstance
      .to receive(:current_user).and_return(create(:user, :agent))

    get '/support/admin/settings/database'

    expect(response).to have_http_status(:redirect)
  end
end
