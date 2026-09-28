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

# /runtime holds exactly the shared libraries a Dart AOT binary needs, laid out
# for an empty image. Copied onto a distro it clashes with merged-/usr (/lib is
# a symlink there), so the image is scratch: no shell, no package manager.
FROM scratch AS runtime
COPY --from=build /runtime/ /
COPY --from=build /build/lobby /app/lobby

# Unprivileged: the lobby opens sockets (its own, and one loopback port per
# room hub) and touches no files. Numeric, since scratch has no /etc/passwd.
USER 10001:10001

# Container-internal only: Caddy is the public edge.
EXPOSE 8080
ENTRYPOINT ["/app/lobby"]
