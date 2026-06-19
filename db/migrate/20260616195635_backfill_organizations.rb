class BackfillOrganizations < ActiveRecord::Migration[8.1]
  def up
    User.find_each do |user|
      next if user.organization_id.present?

      base  = (user.name.presence || user.email.split("@").first).parameterize
      slug  = unique_slug(base)

      org = Organization.create!(
        name: user.name.presence || user.email.split("@").first.titleize,
        slug: slug
      )
      user.update_columns(organization_id: org.id, role: "owner")
    end

    # Propagate organization_id to every resource from the owning user's org.
    {
      Candidate     => :user_id,
      JobRole       => :user_id,
      VideoAnalysis => :user_id,
      CvAnalysis    => :user_id,
      Shortlist     => :user_id
    }.each do |model, fk|
      model.where(organization_id: nil).find_each do |record|
        org_id = User.find_by(id: record.public_send(fk))&.organization_id
        record.update_columns(organization_id: org_id) if org_id
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def unique_slug(base)
    slug  = base.presence || "org"
    taken = Organization.where("slug LIKE ?", "#{slug}%").pluck(:slug).to_set
    return slug unless taken.include?(slug)

    i = 2
    i += 1 while taken.include?("#{slug}-#{i}")
    "#{slug}-#{i}"
  end
end
