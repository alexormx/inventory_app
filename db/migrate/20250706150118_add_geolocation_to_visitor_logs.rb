class AddGeolocationToVisitorLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :visitor_logs, :country, :string
    add_column :visitor_logs, :region, :string
    add_column :visitor_logs, :city, :string
    add_column :visitor_logs, :latitude, :float
    add_column :visitor_logs, :longitude, :float
  end
end
