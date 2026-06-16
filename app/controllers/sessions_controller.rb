class SessionsController < ApplicationController
  layout false, only: :new

  def new
  end

  def destroy
    session.delete(:user_id)
    redirect_to login_path, notice: "Signed out."
  end
end
