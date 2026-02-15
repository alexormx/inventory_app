# frozen_string_literal: true

# config/initializers/geocoder.rb
Geocoder.configure(
  timeout: 5,
  lookup: :ipinfo_io, # usa :ipinfo_io o :ipapi si no estás autenticado
  ip_lookup: :ipinfo_io,
  use_https: true,
  cache: nil,
  units: :km
)
