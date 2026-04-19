class DemoController < ApplicationController
  protect_from_forgery with: :null_session

  before_action :guard_demo

  def picker
    @users = User.order(:id)
    render inline: PICKER_HTML, layout: false
  end

  def login_as
    user = User.find(params[:id])
    session[:demo_user_id] = user.id
    cookies[:demo_user_id] = { value: user.id.to_s, httponly: true, same_site: :lax }
    if user.is_admin? || user.is_agent?
      redirect_to '/support/agent/dashboard'
    else
      redirect_to '/support/customer/tickets'
    end
  end

  def logout
    session[:demo_user_id] = nil
    cookies.delete(:demo_user_id)
    redirect_to demo_picker_path
  end

  private

  def guard_demo
    head :not_found unless Rails.env.demo? || ENV['APP_ENV'] == 'demo'
  end

  PICKER_HTML = <<~HTML.freeze
    <!DOCTYPE html>
    <html lang="en"><head>
      <meta charset="UTF-8"><title>Escalated · Rails Demo</title>
      <style>
        *{box-sizing:border-box}body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
          background:#0f172a;color:#e2e8f0;margin:0;padding:2rem}
        .wrap{max-width:720px;margin:0 auto}
        h1{font-size:1.5rem;margin:0 0 .25rem}p.lede{color:#94a3b8;margin:0 0 2rem}
        .group{margin-bottom:1.5rem}
        .group h2{font-size:.75rem;text-transform:uppercase;letter-spacing:.08em;color:#64748b;margin:0 0 .5rem}
        form{display:block;margin:0}
        button.user{display:flex;width:100%;align-items:center;justify-content:space-between;
          padding:.75rem 1rem;background:#1e293b;border:1px solid #334155;border-radius:8px;
          color:#f1f5f9;font-size:.95rem;cursor:pointer;margin-bottom:.5rem;text-align:left}
        button.user:hover{background:#273549;border-color:#475569}
        .meta{color:#94a3b8;font-size:.8rem}
        .badge{font-size:.7rem;padding:.15rem .5rem;border-radius:999px;background:#334155;color:#cbd5e1;margin-left:.5rem}
        .badge.admin{background:#7c3aed;color:#fff}.badge.agent{background:#0ea5e9;color:#fff}
      </style>
    </head><body><div class="wrap">
      <h1>Escalated Rails Demo</h1>
      <p class="lede">Click a user to log in. Every restart reseeds the database.</p>
      <% @users.each do |u| %>
        <form method="POST" action="/demo/login/<%= u.id %>">
          <input type="hidden" name="authenticity_token" value="<%= form_authenticity_token %>">
          <button type="submit" class="user">
            <span><%= u.name %>
              <% if u.is_admin %><span class="badge admin">Admin</span>
              <% elsif u.is_agent %><span class="badge agent">Agent</span><% end %>
            </span>
            <span class="meta"><%= u.email %></span>
          </button>
        </form>
      <% end %>
    </div></body></html>
  HTML
end
