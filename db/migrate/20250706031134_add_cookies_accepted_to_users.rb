class AddCookiesAcceptedToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :cookies_accepted, :boolean
  end
end
