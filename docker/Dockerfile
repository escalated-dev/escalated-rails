# syntax=docker/dockerfile:1.7

FROM ruby:3.3-alpine AS base

RUN apk add --no-cache build-base postgresql-dev postgresql-client git nodejs npm tzdata

WORKDIR /host

# Bootstrap a minimal Rails 7.1 app skeleton, then depend on the gem from local path.
RUN gem install rails -v '~> 7.1' --no-document \
    && rails new . --database=postgresql --skip-bundle --skip-git --skip-test --skip-system-test --skip-kamal --api=false

# Mount the gem source so we can depend via path:
COPY Gemfile escalated.gemspec /package/
COPY lib /package/lib
COPY app /package/app
COPY config /package/config
COPY db /package/db
COPY stubs /package/stubs

RUN bundle add escalated --path=/package --skip-install \
    && bundle install --jobs 4 --retry 3

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV APP_ENV=demo
EXPOSE 3000

ENTRYPOINT ["entrypoint.sh"]
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
