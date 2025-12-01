# frozen_string_literal: true

ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

require 'bundler/setup' # Set up gems listed in the Gemfile.
# Bootsnap puede interferir con Zeitwerk/load paths en test; lo desactivamos en test
unless ENV['RAILS_ENV'] == 'test'
  require 'bootsnap/setup' # Speed up boot time by caching expensive operations.
end
