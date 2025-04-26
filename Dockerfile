FROM swift:6.0.3-jammy AS build

# Set up a build environment.
WORKDIR /build

# Install the current cross compile SDK, this is cached across builds.
RUN swift sdk install https://download.swift.org/swift-6.0.3-release/static-sdk/swift-6.0.3-RELEASE/swift-6.0.3-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz --checksum 67f765e0030e661a7450f7e4877cfe008db4f57f177d5a08a6e26fd661cdd0bd

# First just resolve dependencies.
# This creates a cached layer that can be reused
# as long as your Package.swift/Package.resolved
# files do not change.
COPY ./Package.* ./
RUN swift package resolve

# Copy entire repo into container.
COPY . .

# Build static executable.
RUN swift build --swift-sdk x86_64-swift-linux-musl -c release

# Switch to a staging area.
WORKDIR /staging

# Copy executable to staging.
RUN cp "$(swift build --package-path /build --swift-sdk x86_64-swift-linux-musl -c release --show-bin-path)/chroma" ./

# Base docker image for minium dependencies.
FROM scratch

# TODO setup a user so we aren't running as root.
WORKDIR /app

# Copy executable from staging.
COPY --from=build /staging /app

ENTRYPOINT ["./chroma"]