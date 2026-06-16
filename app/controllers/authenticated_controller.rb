class AuthenticatedController < ApplicationController
  before_action :authenticate!

  private

  def require_write_access!
    return if current_user.can_write?
    redirect_to root_path, alert: "You don't have permission to perform this action."
  end

  def require_owner!
    return if current_user.owner?
    redirect_to root_path, alert: "Only the organisation owner can do this."
  end
end
