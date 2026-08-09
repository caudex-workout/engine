FROM node:24-bookworm

ARG ZIG_VERSION=0.16.0

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
      build-essential clang curl pkg-config sqlite3 libsqlite3-dev xz-utils \
    && curl --fail --silent --show-error --location \
      "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
      --output /tmp/zig.tar.xz \
    && mkdir -p /opt/zig \
    && tar -xJf /tmp/zig.tar.xz --strip-components=1 -C /opt/zig \
    && ln -s /opt/zig/zig /usr/local/bin/zig \
    && rm -f /tmp/zig.tar.xz \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
