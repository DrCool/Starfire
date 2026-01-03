# Use Debian-based Ruby image with full standard libraries
FROM ruby:3.2.2-bullseye

# Install essential dependencies
RUN apt-get update -qq && apt-get install -y \
    build-essential \
    libssl-dev \
    libyaml-dev \
    libreadline-dev \
    libsqlite3-dev \
    default-libmysqlclient-dev \
    zlib1g-dev \
    git

# Set the working directory
WORKDIR /app

# Copy Gemfile and install gems (caching optimization)
COPY Gemfile Gemfile.lock ./
RUN gem install bundler --no-document && bundle install

# Copy the entire app source
COPY . .

# Set the default command to run your Ruby script
CMD ["ruby", "./lib/server.rb"]
