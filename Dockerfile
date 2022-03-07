FROM ruby:3.0.3
ADD Gemfile /Gemfile
RUN bundle install
ADD entrypoint.rb /entrypoint.rb
RUN chmod +x /entrypoint.rb
ENTRYPOINT ["/entrypoint.rb"]
