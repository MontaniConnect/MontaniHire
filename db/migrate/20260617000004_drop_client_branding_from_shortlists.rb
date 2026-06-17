class DropClientBrandingFromShortlists < ActiveRecord::Migration[8.1]
  def up
    remove_column :shortlists, :client_name,     :string
    remove_column :shortlists, :client_logo_url, :string
  end

  def down
    add_column :shortlists, :client_name,     :string
    add_column :shortlists, :client_logo_url, :string
  end
end
