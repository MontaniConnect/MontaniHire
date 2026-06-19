class AllowNullClientEmailOnShortlists < ActiveRecord::Migration[8.1]
  def change
    change_column_null :shortlists, :client_email, true
  end
end
