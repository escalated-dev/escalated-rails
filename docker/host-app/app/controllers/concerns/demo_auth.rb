module DemoAuth
  extend ActiveSupport::Concern

  def current_user
    return @current_user if defined?(@current_user)

    id = session[:demo_user_id] || cookies[:demo_user_id]
    @current_user = id.present? ? User.find_by(id: id) : nil
  end

  def authenticate_user!
    return if current_user

    redirect_to '/demo'
  end
end
