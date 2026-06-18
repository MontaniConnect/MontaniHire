class AddInterviewCalendarIdToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :interview_calendar_id, :string
  end
end
