# syntax=docker/dockerfile:1.7
FROM ruby:3.3-alpine AS base

RUN apk add --no-cache build-base postgresql-dev postgresql-client git nodejs npm tzdata yaml-dev

WORKDIR /host

# Bootstrap a minimal Rails 7.1 skeleton, then layer the gem + host overrides on top.
RUN gem install rails -v '~> 7.1' --no-document \
    && rails new . --database=postgresql --skip-bundle --skip-git --skip-test --skip-system-test \
       --skip-kamal --skip-jbuilder --skip-action-mailbox --skip-action-text --skip-active-storage \
       --skip-asset-pipeline --skip-javascript --skip-hotwire

# Mount the gem source as a path dep
COPY Gemfile escalated.gemspec /package/
COPY lib /package/lib
COPY app /package/app
COPY config /package/config
COPY db /package/db
COPY stubs /package/stubs

# Replace the host's Gemfile + add the gem via path
COPY docker/host-app/Gemfile /host/Gemfile
RUN bundle install --jobs 4 --retry 3

# Layer host overrides (User, controllers, routes, seed)
COPY docker/host-app/config/routes.rb /host/config/routes.rb
COPY docker/host-app/config/initializers/escalated.rb /host/config/initializers/escalated.rb
COPY docker/host-app/config/environments/demo.rb /host/config/environments/demo.rb
COPY docker/host-app/app/models/user.rb /host/app/models/user.rb
COPY docker/host-app/app/controllers/demo_controller.rb /host/app/controllers/demo_controller.rb
COPY docker/host-app/app/controllers/concerns/demo_auth.rb /host/app/controllers/concerns/demo_auth.rb
COPY docker/host-app/app/views/layouts/application.html.erb /host/app/views/layouts/application.html.erb
COPY docker/host-app/db/migrate/20260418000001_create_users.rb /host/db/migrate/20260418000001_create_users.rb
COPY docker/host-app/db/seeds.rb /host/db/seeds.rb

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV APP_ENV=demo
ENV RAILS_ENV=demo
EXPOSE 3000

ENTRYPOINT ["entrypoint.sh"]
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
