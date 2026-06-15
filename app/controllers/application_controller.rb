class ApplicationController < ActionController::Base
  helper_method :current_user

  def current_user
    @current_user
  end

  private

  def authenticate!
    # In development, auto-sign in as the first user for convenience.
    # Replace with real auth (JWT, Devise, etc.) before production.
    @current_user = User.find_by(id: request.headers["X-User-Id"]) ||
                    (Rails.env.development? ? User.first : nil)

    return if @current_user

    respond_to do |format|
      format.html do
        render plain: "No user account found. Run `rails db:seed` to create one.", status: :unauthorized
      end
      format.json { render json: { error: "Unauthorized" }, status: :unauthorized }
    end
  end
end
