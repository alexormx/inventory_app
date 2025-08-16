web: bundle exec puma -C config/puma.rb

# Release phase to run migrations automatically on deploy
release: bundle exec rails db:migrate

# If you use solid_queue or other background processors, enable a worker dyno:
# worker: bundle exec bin/solid_queue