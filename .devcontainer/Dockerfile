FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

USER root

# Install dependencies: Chromium, SQLite3, git, curl, unzip
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    sqlite3 \
    libsqlite3-dev \
    chromium-browser \
    && rm -rf /var/lib/apt/lists/*

USER vscode
WORKDIR /home/vscode

# Install Flutter SDK (stable)
ENV FLUTTER_CHANNEL="stable"
ENV FLUTTER_VERSION="3.29.0"
ENV FLUTTER_HOME="/home/vscode/flutter"
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}"
ENV CHROME_EXECUTABLE="/usr/bin/chromium-browser"

RUN git clone -b ${FLUTTER_CHANNEL} https://github.com/flutter/flutter.git ${FLUTTER_HOME} && \
    flutter config --no-analytics && \
    flutter precache --web && \
    flutter doctor -v
