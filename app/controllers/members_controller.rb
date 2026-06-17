class MembersController < AuthenticatedController
  before_action :require_owner!
  before_action :set_member

  ASSIGNABLE_ROLES = %w[member viewer].freeze

  def update
    new_role = params[:role].to_s
    unless ASSIGNABLE_ROLES.include?(new_role)
      return redirect_to settings_path, alert: "Invalid role."
    end

    if sole_owner_demotion?
      return redirect_to settings_path,
        alert: "You can't change your own role — you're the only owner. Assign another owner first."
    end

    @member.update!(role: new_role)
    redirect_to settings_path, notice: "#{member_display_name} is now a #{new_role.titleize}."
  end

  def destroy
    if @member == current_user && current_organization.sole_owner?(current_user)
      return redirect_to settings_path,
        alert: "You can't remove yourself — you're the only owner. Assign another owner first."
    end

    @member.update!(organization: nil, role: "member")
    redirect_to settings_path, notice: "#{member_display_name} has been removed from the organisation."
  end

  private

  def set_member
    @member = current_organization.users.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to settings_path, alert: "Member not found."
  end

  def sole_owner_demotion?
    @member == current_user &&
      @member.owner? &&
      current_organization.sole_owner?(current_user)
  end

  def member_display_name
    @member.name.presence || @member.email
  end
end
