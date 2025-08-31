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

  desc 'Genera variantes redimensionadas (-{w}w.ext) y modernas (avif/webp) para responsive_asset_image'
  task generate_responsive_variants: :environment do
    require 'mini_magick'
    base = Rails.root.join('app','assets','images')
    widths = (ENV['WIDTHS'] || '480,768,1200').split(',').map(&:to_i).select{|w| w>0}
    exts = %w[jpg jpeg png]
    created = 0
    Dir.chdir(base) do
      Dir.glob("*.{#{exts.join(',')}}").each do |file|
        next if file.start_with?('favicon')
        size = File.size(file) rescue 0
        next if size < 120*1024 # omitir imágenes pequeñas
        orig = MiniMagick::Image.open(file)
        widths.each do |w|
          extless = file.sub(/\.[^.]+$/,'')
          original_ext = File.extname(file).delete('.')
          target_base = "#{extless}-#{w}w"
          # Formatos originales y modernos
          [original_ext, 'webp', 'avif'].each do |fmt|
            target = "#{target_base}.#{fmt}"
            next if File.exist?(target)
            begin
              img = orig.clone
              img.resize "#{w}x" # mantiene aspecto
              case fmt
              when 'webp'
                img.format 'webp' do |c| c.quality '72'; end
              when 'avif'
                img.format 'avif' do |c| c.quality '50'; end
              else
                # JPEG/PNG: ajustar calidad sólo si es jpeg
                if fmt =~ /jpe?g/i
                  img.quality '80'
                end
              end
              img.write target
              created += 1
              puts "-> #{target}" if ENV['VERBOSE']
            rescue => e
              warn "ERROR #{file} -> #{target}: #{e.message}"
            end
          end
        end
      end
    end
    puts "Listo. #{created} variantes responsive creadas.";
  end
end
