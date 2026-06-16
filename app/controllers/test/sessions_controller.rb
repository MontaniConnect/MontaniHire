class Test::SessionsController < ApplicationController
  def create
    session[:user_id] = params[:user_id].to_i
    head :ok
  end
end
