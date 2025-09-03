namespace :sepomex do
  desc 'Import SEPOMEX postal codes from CSV: rake sepomex:import[path/to/file.csv]'
  task :import, [:path] => :environment do |t, args|
    path = args[:path]
    unless path
      puts 'Usage: rake sepomex:import[path/to/file.csv]'
      exit 1
    end
    importer = Sepomex::Importer.new(path)
    count = importer.call
    puts "Imported #{count} rows"
  end
end
