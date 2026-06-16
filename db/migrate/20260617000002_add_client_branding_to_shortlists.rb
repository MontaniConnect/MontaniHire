class AddClientBrandingToShortlists < ActiveRecord::Migration[8.0]
  def change
    add_column :shortlists, :client_name,     :string
    add_column :shortlists, :client_logo_url, :string
  end
end
