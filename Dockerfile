FROM ruby:2.5.1-alpine

WORKDIR work

ENV RUBY_PACKAGES "ruby ruby-dev ruby-bundler ruby-io-console libffi-dev build-base"
RUN apk --no-cache add $RUBY_PACKAGES

COPY Gemfile      /work/Gemfile
COPY Gemfile.lock /work/Gemfile.lock

RUN bundle install -j 2

COPY bin /work/bin
COPY lib /work/lib

ENTRYPOINT ["bundle", "exec", "bin/rodgers"]

