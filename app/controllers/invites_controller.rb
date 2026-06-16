class InvitesController < AuthenticatedController
  before_action :require_owner!, only: %i[create destroy]
  skip_before_action :authenticate!, only: %i[show accept]

  def create
    @invite = current_organization.invites.build(
      email:      params[:invite][:email].to_s.strip.downcase,
      role:       params[:invite][:role],
      invited_by: current_user
    )
    if @invite.save
      redirect_to settings_path, notice: "Invite created — copy the link below and send it to #{@invite.email}."
    else
      redirect_to settings_path, alert: @invite.errors.full_messages.to_sentence
    end
  end

  def destroy
    invite = current_organization.invites.find(params[:id])
    invite.destroy
    redirect_to settings_path, notice: "Invite revoked."
  end

  def show
    @invite = Invite.find_by(token: params[:token])
    if @invite.nil? || @invite.accepted? || @invite.expired?
      redirect_to login_path, alert: "This invite link is invalid or has expired."
    end
  end

  def accept
    @invite = Invite.find_by(token: params[:token])
    if @invite.nil? || @invite.accepted? || @invite.expired?
      redirect_to login_path, alert: "This invite link is invalid or has expired."
      return
    end

    unless current_user
      session[:return_to] = accept_join_path(params[:token])
      redirect_to login_path, alert: "Please sign in with Google to accept this invite."
      return
    end

    if current_user.email.downcase != @invite.email
      redirect_to join_path(@invite.token),
                  alert: "This invite was sent to #{@invite.email} but you're signed in as #{current_user.email}."
      return
    end

    if current_user.organization.present? && current_user.organization != @invite.organization
      redirect_to join_path(@invite.token),
                  alert: "You already belong to another organisation. Please contact your admin."
      return
    end

    @invite.accept!(current_user)
    redirect_to root_path, notice: "Welcome to #{@invite.organization.name}!"
  end
end
