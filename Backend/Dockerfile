# syntax=docker/dockerfile:1
# ==============================================================================
# Stage 1: Build (Docs/product-deployment.md §18)
# swift:6.1 on Ubuntu 22.04 (jammy) so the produced binary is ABI-compatible
# with the ubuntu:22.04 runtime stage. Works for both linux/amd64 and linux/arm64
# (buildx selects the matching base per target platform).
# ==============================================================================
FROM swift:6.1-jammy AS build

# Install build-time system dependencies.
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get -q install -y libjemalloc-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Resolve dependencies first so this layer is cached unless the manifests change.
COPY ./Package.* ./
RUN swift package resolve \
        $([ -f ./Package.resolved ] && echo "--force-resolved-versions" || true)

# Copy the full source and build the release binary.
COPY . .
RUN swift build -c release \
        --product App \
        --static-swift-stdlib \
        -Xlinker -ljemalloc

# Collect the binary (and any resource bundles) into a clean staging directory.
WORKDIR /staging
RUN cp "$(swift build --package-path /build -c release --show-bin-path)/App" ./
RUN find -L "$(swift build --package-path /build -c release --show-bin-path)/" -regex '.*\.resources$' -exec cp -Ra {} ./ \; || true
# Leaf templates for the web admin dashboard (Docs/product-web.md §12).
RUN [ -d /build/Resources ] && cp -Ra /build/Resources ./Resources || true
# Static assets (CSS) served by FileMiddleware for the web UIs.
RUN [ -d /build/Public ] && cp -Ra /build/Public ./Public || true
# Version file read at startup for the footer (Site Settings & Admin Customization).
RUN [ -f /build/VERSION ] && cp /build/VERSION ./VERSION || true

# ==============================================================================
# Stage 2: Runtime (Docs/product-deployment.md §18)
# Minimal ubuntu:22.04 image: the compiled binary plus only the required
# system libraries. No Swift toolchain, no source.
# ==============================================================================
FROM ubuntu:22.04

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get -q install -y \
        libjemalloc2 \
        ca-certificates \
        tzdata \
        libcurl4 \
        libxml2 \
    && rm -rf /var/lib/apt/lists/*

# Run as an unprivileged user.
RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app stash

WORKDIR /app
COPY --from=build --chown=stash:stash /staging /app

USER stash:stash

EXPOSE 8080
ENTRYPOINT ["./App"]
# Migrations run automatically on boot (see configure.swift); just serve.
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
