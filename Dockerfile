FROM node:latest as frontend
WORKDIR /usr/src/app/
COPY ./frontend .
RUN rm -rf .parcel-cache && rm -rf ./dist
RUN npm install && npm run build:docker && cp -r ./lib ./dist

FROM rust:latest as backend

# Install required dependencies for Vosk linking
RUN apt-get update && apt-get install -y \
    build-essential \
    gfortran \
    curl \
    libstdc++6 \
    libgfortran5 \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Download REAL Linux x86_64 Vosk library from GitHub Release
RUN curl -L -o /usr/local/lib/libvosk.so \
        https://github.com/viveksapkal2793/AuraTalk/releases/download/vosk/libvosk.so \
    && cp /usr/local/lib/libvosk.so /usr/lib/libvosk.so \
    && mkdir -p /usr/lib/x86_64-linux-gnu \
    && cp /usr/local/lib/libvosk.so /usr/lib/x86_64-linux-gnu/libvosk.so \
    && ldconfig \
    && ls -lh /usr/lib/libvosk.so /usr/lib/x86_64-linux-gnu/libvosk.so

# Download model (instead of using your LFS folder)
RUN mkdir -p /usr/src/app/model \
    && curl -L -o model.zip \
        https://github.com/viveksapkal2793/AuraTalk/releases/download/vosk_model/vosk-model-small-en-us-0.15.zip \
    && unzip model.zip -d /usr/src/app/model \
    && rm model.zip

# Copy model files BEFORE cargo build
# COPY ./model /usr/src/app/model

WORKDIR /usr/src/app
COPY . .

# Set library path for the linker
ENV LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

# Will build and cache the binary and dependent crates in release mode
# RUN --mount=type=cache,target=/usr/local/cargo,from=rust:latest,source=/usr/local/cargo \
#     --mount=type=cache,target=target \
#     cargo build --release && mv ./target/release/speech-rs ./speech-rs

# Simplified build without cache mounts for Railway compatibility
RUN cargo build --release && mv ./target/release/speech-rs ./speech-rs

# Runtime image
# FROM rust:latest

# Runtime image
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libstdc++6 \
    libgfortran5 \
    && rm -rf /var/lib/apt/lists/*

# Run as "app" user
RUN useradd -ms /bin/bash app

USER app
WORKDIR /app

# Get compiled binaries from builder's cargo install directory
COPY --from=backend /usr/src/app/speech-rs /app/speech-rs
COPY --from=backend /usr/src/app/model /app/model
COPY --from=backend /usr/local/lib/libvosk.so /usr/local/lib/libvosk.so
COPY --from=frontend /usr/src/app/dist /app/public

ENV LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

# Run the app
EXPOSE 3000
CMD ./speech-rs