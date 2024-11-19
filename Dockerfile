# openjdk docker image version from https://hub.docker.com/_/openjdk : *stable* version (no 'ea' or 'rc'), using newest available debian base
FROM openjdk:20-jdk-bullseye

RUN apt-get update

# install "zip" (useful for handling AARs and JARs manually)
RUN apt-get install -y --no-install-recommends zip

# Android conf
## Command Line Tools url from https://developer.android.com/studio#command-line-tools-only
ENV SDK_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
## Android version from the latest API in Android Studio
ENV ANDROID_VERSION=35
## Build Tools version from https://developer.android.com/tools/releases/build-tools#notes
ENV ANDROID_BUILD_TOOLS_VERSION=34.0.0
## NDK version from https://developer.android.com/ndk/downloads
ENV NDK_VER="27.2.12479018"

# GoLang conf
## Go version & hash from https://go.dev/dl/ (Hash from Archive Linux x86-64) : debian bullseye provides go1.15.15, which can only build go source up to go 1.19
ENV GOLANG_VERSION=1.23.3
ENV GOLANG_SHA256=a0afb9744c00648bafb1b90b4aba5bdb86f424f02f9275399ce0c20b93a2c3a8
## GoMobile version from https://github.com/golang/mobile (Latest commit, as there is no tag yet)
ENV GOMOBILEHASH=fa514ef75a0ffd7d89e1b4c9b45485f7bb39cf83

## --- END OF VARIABLES TO CHANGE FOR UPDATE ---

# Android section of this Dockerfile from https://medium.com/@elye.project/intro-to-docker-building-android-app-cb7fb1b97602
## Download Android SDK
ENV ANDROID_HOME="/usr/local/android-sdk"
ENV ANDROID_SDK=$ANDROID_HOME
RUN mkdir "$ANDROID_HOME" .android \
    && mkdir -p $ANDROID_HOME/cmdline-tools/latest/ \
    && cd "$ANDROID_HOME" \
    && curl -o sdk-commandlinetools.zip $SDK_URL \
    && unzip sdk-commandlinetools.zip -d cmdline-tools \
    && rm sdk-commandlinetools.zip
RUN ls $ANDROID_HOME
RUN ls $ANDROID_HOME/cmdline-tools/cmdline-tools/bin/
RUN mv $ANDROID_HOME/cmdline-tools/cmdline-tools/* $ANDROID_HOME/cmdline-tools/latest/
RUN ls $ANDROID_HOME/cmdline-tools/latest/
RUN ls $ANDROID_HOME/cmdline-tools/latest/bin/
RUN yes | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --licenses

## Install Android Build Tool and Libraries
RUN $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --update
RUN $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager "build-tools;${ANDROID_BUILD_TOOLS_VERSION}" \
    "platforms;android-${ANDROID_VERSION}" \
    "platform-tools"

# Install NDK
RUN $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager "ndk;$NDK_VER"
RUN ln -sf $ANDROID_HOME/ndk/$NDK_VER $ANDROID_HOME/ndk-bundle

# Go section of this Dockerfile from Docker golang: https://github.com/docker-library/golang/blob/master/1.21/bullseye/Dockerfile
# Adapted from alpine apk to debian apt

## set up nsswitch.conf for Go's "netgo" implementation
## - https://github.com/golang/go/blob/go1.9.1/src/net/conf.go#L194-L275
## - docker run --rm debian:stretch grep '^hosts:' /etc/nsswitch.conf
RUN echo 'hosts: files dns' > /etc/nsswitch.conf

# install cgo-related dependencies
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		g++ \
		gcc \
		libc6-dev \
		make \
		pkg-config \
	; \
	rm -rf /var/lib/apt/lists/*

ENV PATH=/usr/local/go/bin:$PATH
RUN set -eux; \
	arch="$(dpkg --print-architecture)"; arch="${arch##*-}"; \
	url=; \
	case "$arch" in \
		'amd64') \
			url="https://dl.google.com/go/go$GOLANG_VERSION.linux-amd64.tar.gz"; \
			;; \
		*) echo >&2 "error: unsupported architecture '$arch' (likely packaging update needed)"; exit 1 ;; \
	esac; \
	wget -O go.tgz.asc "$url.asc"; \
	wget -O go.tgz "$url" --progress=dot:giga;

RUN	echo "$GOLANG_SHA256 *go.tgz" | sha256sum -c -;

RUN set -eux; \
# https://github.com/golang/go/issues/14739#issuecomment-324767697
	GNUPGHOME="$(mktemp -d)"; export GNUPGHOME; \
# https://www.google.com/linuxrepositories/
	gpg --batch --keyserver keyserver.ubuntu.com --recv-keys 'EB4C 1BFD 4F04 2F6D DDCC  EC91 7721 F63B D38B 4796'; \
# let's also fetch the specific subkey of that key explicitly that we expect "go.tgz.asc" to be signed by, just to make sure we definitely have it
	gpg --batch --keyserver keyserver.ubuntu.com --recv-keys '2F52 8D36 D67B 69ED F998  D857 78BD 6547 3CB3 BD13'; \
	gpg --batch --verify go.tgz.asc go.tgz; \
	gpgconf --kill all; \
	rm -rf "$GNUPGHOME" go.tgz.asc; \
	\
	tar -C /usr/local -xzf go.tgz; \
	rm go.tgz; \
	\
	go version

# persist new go in PATH
ENV PATH=/usr/local/go/bin:$PATH

ENV GOMOBILEPATH=/gomobile
# Setup /workspace
RUN mkdir $GOMOBILEPATH
# Set up GOPATH in /workspace
ENV GOPATH=$GOMOBILEPATH
ENV PATH=$GOMOBILEPATH/bin:$PATH
RUN mkdir -p "$GOMOBILEPATH/src" "$GOMOBILEPATH/bin" "$GOMOBILEPATH/pkg" && chmod -R 777 "$GOMOBILEPATH"

# install gomobile
RUN cd $GOMOBILEPATH/src; \
       mkdir -p golang.org/x; \
       cd golang.org/x; \
       git clone https://github.com/golang/mobile.git; \
       cd mobile; \
       git checkout $GOMOBILEHASH;

RUN go install golang.org/x/mobile/cmd/gomobile@$GOMOBILEHASH
RUN go install golang.org/x/mobile/cmd/gobind@$GOMOBILEHASH

RUN gomobile clean

# cleanup
RUN rm -rf /var/lib/apt/lists/*
