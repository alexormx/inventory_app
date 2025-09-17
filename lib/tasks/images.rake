# frozen_string_literal: true

# Rake task para convertir imágenes JPG/PNG a WebP y AVIF en app/assets/images
# Requiere gems: image_processing, mini_magick
# Uso:
#   bin/rails images:convert              # convierte todos los .jpg/.jpeg/.png a .webp y .avif
#   bin/rails images:convert[force]       # fuerza recreación aunque existan
#   bin/rails images:report               # lista tamaños y ahorro estimado

require 'image_processing/vips' rescue nil
require 'image_processing/mini_magick' rescue nil

namespace :images do
  IMAGE_DIR = Rails.root.join('app', 'assets', 'images')
  SOURCE_EXT = %w[.jpg .jpeg .png].freeze

  def processor
    # Prefer vips si está disponible por rendimiento; fallback a mini_magick
    if defined?(ImageProcessing::Vips)
      ImageProcessing::Vips
    else
      ImageProcessing::MiniMagick
    end
  end

  def convert_one(src_path, dest_path, format:, quality: 82)
    proc = processor.source(src_path)
    FileUtils.mkdir_p(File.dirname(dest_path))
    case format
    when :webp
      proc.convert('webp').saver(quality: quality).call(destination: dest_path)
    when :avif
      # Para AVIF con vips: saver(quality: 45); con mini_magick usamos libaom parameters
      if defined?(ImageProcessing::Vips)
        proc.convert('avif').saver(quality: 45).call(destination: dest_path)
      else
        proc.convert('avif').call(destination: dest_path)
      end
    else
      raise "Formato no soportado: #{format}"
    end
  end

  def bytes(n)
    units = %w[B KiB MiB GiB]
    i = 0
    while n > 1024 && i < units.length - 1
      n /= 1024.0
      i += 1
    end
    format('%.1f %s', n, units[i])
  end

  desc 'Convierte JPG/PNG a WebP y AVIF (argumento opcional: force)'
  task :convert, [:force] => :environment do |_t, args|
    force = args[:force].to_s == 'force'
    Dir.glob(IMAGE_DIR.join('**', '*')).each do |path|
      next unless SOURCE_EXT.include?(File.extname(path).downcase)
      base = path.sub(/\.(jpg|jpeg|png)$/i, '')
      webp = base + '.webp'
      avif = base + '.avif'

      [[:webp, webp], [:avif, avif]].each do |fmt, dest|
        next if File.exist?(dest) && !force
        puts "→ #{File.basename(path)} -> #{File.basename(dest)}"
        begin
          convert_one(path, dest, format: fmt)
        rescue => e
          warn "Error convirtiendo #{path} a #{fmt}: #{e.message}"
        end
      end
    end
  end

  desc 'Reporte de tamaños y ahorro estimado (si .webp/.avif existen)'
  task :report => :environment do
    summary = []
    Dir.glob(IMAGE_DIR.join('**', '*')).each do |path|
      next unless SOURCE_EXT.include?(File.extname(path).downcase)
      base = path.sub(/\.(jpg|jpeg|png)$/i, '')
      webp = base + '.webp'
      avif = base + '.avif'
      orig = File.size?(path) || 0
      webp_size = File.size?(webp) || 0
      avif_size = File.size?(avif) || 0
      best = [webp_size, avif_size].reject(&:zero?).min || 0
      saving = [orig - best, 0].max
      summary << [path.sub(IMAGE_DIR.to_s + '/', ''), orig, webp_size, avif_size, saving]
    end

    total_orig = summary.sum { |r| r[1] }
    total_best = summary.sum { |r| [r[2], r[3]].reject(&:zero?).min || 0 }
    total_saving = [total_orig - total_best, 0].max

    puts 'Archivo, Original, WebP, AVIF, Ahorro'
    summary.each do |row|
      puts [row[0], bytes(row[1]), bytes(row[2]), bytes(row[3]), bytes(row[4])].join(', ')
    end
    puts '---'
    puts "Total original: #{bytes(total_orig)}"
    puts "Total optimizado (mejor de WebP/AVIF): #{bytes(total_best)}"
    puts "Ahorro estimado: #{bytes(total_saving)}"
  end
end
