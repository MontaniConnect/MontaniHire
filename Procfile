web:     bundle exec puma -C config/puma.rb
worker:  bundle exec sidekiq -c 3
release: bundle exec rails db:migrate SKIP_CABLE_DB=true
