FROM ruby:3.1.2
ADD Gemfile /Gemfile
RUN bundle install
ADD entrypoint.rb /entrypoint.rb
RUN chmod +x /entrypoint.rb
ENTRYPOINT ["/entrypoint.rb"]
