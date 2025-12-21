class CreateNewsletterSubscribers < ActiveRecord::Migration[8.0]
  def change
    create_table :newsletter_subscribers do |t|
      t.string :email
      t.datetime :subscribed_at
      t.datetime :unsubscribed_at

      t.timestamps
    end
    add_index :newsletter_subscribers, :email, unique: true
  end
end
