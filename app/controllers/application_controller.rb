class ApplicationController < ActionController::Base
  helper_method :current_user, :current_organization

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def current_organization
    return nil if current_user&.super_admin?
    @current_organization ||= current_user&.organization
  end

  private

  def authenticate!
    return if current_user

    session[:return_to] = request.fullpath if request.get?
    redirect_to login_path, alert: "Please sign in to continue."
  end
end
