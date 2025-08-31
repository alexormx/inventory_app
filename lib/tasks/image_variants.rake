namespace :images do
  desc 'Genera versiones AVIF y WebP para imágenes grandes en app/assets/images'
  task generate_modern_formats: :environment do
    require 'mini_magick'
    base = Rails.root.join('app','assets','images')
    patterns = %w[*.jpg *.jpeg *.png]
    exts = ['avif','webp']
    count = 0
    Dir.chdir(base) do
      patterns.each do |pat|
        Dir.glob(pat).each do |file|
          next if file.start_with?('favicon')
          extless = file.sub(/\.[^.]+$/,'')
          exts.each do |fmt|
            target = "#{extless}.#{fmt}"
            next if File.exist?(target)
            image = MiniMagick::Image.open(file)
            # Sólo convertir si pesa > 150KB para ahorrar tiempo
            if File.size(file) > 150*1024
              puts "-> Generando #{target}";
              image.format(fmt) do |c|
                c.quality '70'
              end
              image.write(target)
              count += 1
            end
          rescue => e
            warn "ERROR #{file} -> #{fmt}: #{e.message}"
          end
        end
      end
    end
    puts "Listo. #{count} variantes creadas.";
  end
end
