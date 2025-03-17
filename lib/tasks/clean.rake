namespace :tmp do
  desc "Clean Capybara screenshots"
  task clear_screenshots: :environment do
    FileUtils.rm_rf(Rails.root.join("tmp/capybara"))
    puts "✅ Capybara screenshots cleared!"
  end
end
