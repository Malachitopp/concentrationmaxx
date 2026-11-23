# ConcentrationMaxx account server: a two-stage build based on Vapor's own template.
# Build:   docker build -t concentrationmaxx-server server/
# Run:     docker run --env-file server/.env -p 8080:8080 concentrationmaxx-server
# The app reads MONGODB_URI, JWT_SECRET and INVITE_CODE from the environment (see .env.example)
# and listens on $PORT (default 8080).

# ================================
# Build image
# ================================
FROM swift:6.3-noble AS build

# Install OS updates and jemalloc
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get install -y libjemalloc-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Resolve dependencies first, so this layer is cached while only sources change.
COPY ./Package.* ./
RUN swift package resolve \
        $([ -f ./Package.resolved ] && echo "--force-resolved-versions" || true)

COPY . .

RUN mkdir /staging

# Optimised, statically linked Swift runtime, with jemalloc.
RUN --mount=type=cache,target=/build/.build \
    swift build -c release \
        --product App \
        --static-swift-stdlib \
        -Xlinker -ljemalloc && \
    cp "$(swift build -c release --show-bin-path)/App" /staging && \
    find -L "$(swift build -c release --show-bin-path)" -regex '.*\.resources$' -exec cp -Ra {} /staging \;

WORKDIR /staging

# Swift's static crash backtracer
RUN cp "/usr/libexec/swift/linux/swift-backtrace-static" ./

# ================================
# Run image
# ================================
FROM ubuntu:noble

# ca-certificates is required for TLS to MongoDB Atlas.
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get -q install -y \
      libjemalloc2 \
      ca-certificates \
      tzdata \
    && rm -r /var/lib/apt/lists/*

# Run as an unprivileged user
RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor

WORKDIR /app

COPY --from=build --chown=vapor:vapor /staging /app

ENV SWIFT_BACKTRACE=enable=yes,sanitize=yes,threads=all,images=all,interactive=no,swift-backtrace=./swift-backtrace-static

USER vapor:vapor

EXPOSE 8080

ENTRYPOINT ["./App"]
# No --port here on purpose: configure.swift reads $PORT, which most hosts set.
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0"]
