FROM rust:latest

# Install Dart
RUN apt-get update && apt-get install -y apt-transport-https wget gnupg
RUN wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/dart.gpg
RUN echo 'deb [signed-by=/usr/share/keyrings/dart.gpg] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main' > /etc/apt/sources.list.d/dart.list
RUN apt-get update && apt-get install -y dart protobuf-compiler

# Install Dart protoc plugin
RUN dart pub global activate protoc_plugin
ENV PATH="$PATH":"/root/.pub-cache/bin"

WORKDIR /workspace
