# syntax=docker/dockerfile:1

# Base images are pinned by digest; Dependabot keeps tag and digest current.
FROM ruby:4.0.9-alpine3.24@sha256:d0c5befc0864d31c6219321c8d79de2941d1bc31c41505d9c9289c6192c36d60 AS build

RUN apk add --no-cache build-base openssl-dev yaml-dev

ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_PATH=/usr/local/bundle

WORKDIR /app
COPY Gemfile Gemfile.lock .ruby-version ./
RUN bundle install --jobs 4 \
    && rm -rf /usr/local/bundle/cache /usr/local/bundle/ruby/*/cache \
    && find /usr/local/bundle -type f \( -name "*.o" -o -name "*.c" -o -name "*.h" -o -name "Makefile" -o -name "mkmf.log" \) -delete \
    && find /usr/local/bundle/ruby/*/gems -maxdepth 2 -type d \( -name test -o -name spec -o -name examples -o -name ext \) -prune -exec rm -rf {} +

COPY bin/garmin-mcp bin/healthcheck bin/
COPY lib lib
COPY data data

FROM ruby:4.0.9-alpine3.24@sha256:d0c5befc0864d31c6219321c8d79de2941d1bc31c41505d9c9289c6192c36d60

ARG VERSION=dev
LABEL org.opencontainers.image.title="garmin-connect-personal-api-mcp" \
      org.opencontainers.image.description="MCP server for the Garmin Connect Personal API" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="${VERSION}"

ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_APP_CONFIG=/usr/local/bundle \
    HOME=/nonexistent \
    GARMIN_MCP_HOST=0.0.0.0 \
    GARMIN_MCP_PORT=8080

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /app /app
WORKDIR /app

# Unprivileged, no home directory, nothing writable: runs with a read-only root filesystem.
USER 65532:65532
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["ruby", "/app/bin/healthcheck"]

ENTRYPOINT ["/app/bin/garmin-mcp"]
CMD ["http"]
