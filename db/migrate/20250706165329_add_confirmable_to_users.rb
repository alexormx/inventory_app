class AddConfirmableToUsers < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :confirmation_token, :string
    add_column :users, :confirmed_at, :datetime
    add_column :users, :confirmation_sent_at, :datetime
    add_column :users, :unconfirmed_email, :string
    add_index  :users, :confirmation_token, unique: true

    # Confirm all existing users immediately (for backward compatibility)
    User.update_all confirmed_at: Time.current
  end

  def down
    remove_index  :users, :confirmation_token
    remove_columns :users, :confirmation_token, :confirmed_at, :confirmation_sent_at, :unconfirmed_email
  end
end
