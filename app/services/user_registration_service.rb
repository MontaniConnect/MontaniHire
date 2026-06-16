class UserRegistrationService
  Result = Data.define(:user, :created)

  def initialize(email:, name:)
    @email = email
    @name  = name
  end

  def call
    existing = User.find_by(email: @email)
    return Result.new(user: existing, created: false) if existing

    user = nil
    ActiveRecord::Base.transaction do
      org  = Organization.create!(name: org_name)
      user = User.create!(email: @email, name: @name, organization: org, role: "owner")
    end

    Result.new(user: user, created: true)
  end

  private

  def org_name
    @name.presence || @email.split("@").first.titleize
  end
end
