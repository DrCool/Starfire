FROM ruby:3.2.2-bullseye

WORKDIR /app

# Install bundler
RUN gem install bundler

# Copy and install gem dependencies
COPY Gemfile Gemfile.lock* ./
RUN bundle install

# Copy the rest of the code
COPY . .

EXPOSE 4567

# You can either run the Sinatra app directly...
CMD ["ruby", "app.rb"]
# ...or use a Rack server (uncomment below if preferred)
# CMD ["rackup", "--port", "4567", "--host", "0.0.0.0"]

