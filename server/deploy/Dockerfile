# The lobby as a self-contained native binary.
# Build context is server/ (docker-compose.yml sets it).
FROM dart:stable AS build

WORKDIR /build
COPY pubspec.yaml ./
COPY bin/ bin/
COPY lib/ lib/
# pubspec_overrides.yaml (local path deps for development) is deliberately
# not copied: the image builds from pub.dev only. Test-only dependencies are
# dropped too (dev_dependencies is the last section of pubspec.yaml), so the
# image never depends on test tooling resolving.
RUN sed -i '/^dev_dependencies:/,$d' pubspec.yaml \
    && dart pub get \
    && dart compile exe bin/lobby.dart -o /build/lobby

FROM debian:bookworm-slim AS runtime
COPY --from=build /runtime/ /
COPY --from=build /build/lobby /app/lobby

# Unprivileged: the lobby opens sockets (its own, and one loopback port per
# room hub) and touches no files.
RUN useradd --system --uid 10001 --no-create-home lobby
USER lobby

# Container-internal only: Caddy is the public edge.
EXPOSE 8080
ENTRYPOINT ["/app/lobby"]
