# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t extract_vid .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name extract_vid extract_vid

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.3.2
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages (postgresql-client-18 requires the PGDG apt repository)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl gnupg2 && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
         | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
         > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y ffmpeg libgcc-s1 libgomp1 libstdc++6 libjemalloc2 libvips postgresql-client-18 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Download whisper-cli pre-built binary (v1.9.0, Linux x86-64)
# glibc requirement: ≤2.34 — Debian bookworm ships 2.36, compatible
RUN curl -fL --retry 3 --retry-delay 10 \
         "https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.0/whisper-bin-ubuntu-x64.tar.gz" \
         -o /tmp/whisper.tar.gz && \
    tar -xzf /tmp/whisper.tar.gz --strip-components=1 -C /tmp whisper-bin-ubuntu-x64/whisper-cli && \
    install -m 755 /tmp/whisper-cli /usr/local/bin/whisper-cli && \
    rm /tmp/whisper.tar.gz /tmp/whisper-cli

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Download Whisper model — before COPY . . so this layer survives code-only rebuilds
RUN mkdir -p vendor/whisper_models && \
    curl -fL --retry 3 --retry-delay 10 \
         "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin" \
         -o vendor/whisper_models/ggml-small.en.bin

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompile assets into public/assets so Propshaft can serve digested filenames in production.
# SECRET_KEY_BASE is not needed at build time — Propshaft asset compilation does not touch the DB or credentials.
RUN SECRET_KEY_BASE=dummy bundle exec rails assets:precompile




# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application, whisper-cli binary
COPY --from=build /usr/local/bin/whisper-cli /usr/local/bin/whisper-cli
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
