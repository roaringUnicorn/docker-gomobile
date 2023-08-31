# openjdk docker image version from https://hub.docker.com/_/openjdk : *stable* version (no 'ea' or 'rc'), using newest available debian base
FROM openjdk:20-jdk-bullseye

RUN apt-get update

# Android conf
## Command Line Tools url from https://developer.android.com/studio#command-line-tools-only
ENV SDK_URL="https://dl.google.com/android/repository/commandlinetools-linux-10406996_latest.zip"
ENV ANDROID_VERSION=33
## Build Tools version from https://developer.android.com/tools/releases/build-tools#notes
ENV ANDROID_BUILD_TOOLS_VERSION=33.0.2
## NDK version from https://developer.android.com/ndk/downloads
ENV NDK_VER="25.2.9519653"

# GoLang conf
## Go version & hash from https://go.dev/dl/ (Source package) : debian bullseye provides go1.15.15, which can only build go source up to go 1.19
ENV GOLANG_VERSION=1.19.12
ENV GOLANG_SHA256=ee5d50e0a7fd74ba1b137cb879609aaaef9880bf72b5d1742100e38ae72bb557
## GoMobile version from https://github.com/golang/mobile (Latest commit, as there is no tag yet)
ENV GOMOBILEHASH=7088062f872dd0678a87e8986c67992e9c8855a5

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

# Go section of this Dockerfile from Docker golang: https://github.com/docker-library/golang/blob/master/1.10/alpine3.8/Dockerfile
# Adapted from alpine apk to debian apt

## set up nsswitch.conf for Go's "netgo" implementation
## - https://github.com/golang/go/blob/go1.9.1/src/net/conf.go#L194-L275
## - docker run --rm debian:stretch grep '^hosts:' /etc/nsswitch.conf
RUN echo 'hosts: files dns' > /etc/nsswitch.conf

RUN set -eux; \
	apt-get install -y --no-install-recommends \
		 bash \
		build-essential \
		openssl \
		libssl-dev \
		golang \
	; \
	export \
## set GOROOT_BOOTSTRAP such that we can actually build Go
		GOROOT_BOOTSTRAP="$(go env GOROOT)" \
## ... and set "cross-building" related vars to the installed system's values so that we create a build targeting the proper arch
## (for example, if our build host is GOARCH=amd64, but our build env/image is GOARCH=386, our build needs GOARCH=386)
		GOOS="$(go env GOOS)" \
		GOARCH="$(go env GOARCH)" \
		GOHOSTOS="$(go env GOHOSTOS)" \
		GOHOSTARCH="$(go env GOHOSTARCH)" \
	; \
## also explicitly set GO386 and GOARM if appropriate
## https://github.com/docker-library/golang/issues/184
	aptArch="$(dpkg-architecture  -q DEB_BUILD_GNU_CPU)"; \
	case "$aptArch" in \
		arm) export GOARM='6' ;; \
		x86_64) export GO386='387' ;; \
	esac; \
	\
	wget -O go.tgz "https://go.dev/dl/go$GOLANG_VERSION.src.tar.gz"; \
	echo "$GOLANG_SHA256 *go.tgz" | sha256sum -c -; \
	tar -C /usr/local -xzf go.tgz; \
	rm go.tgz; \
	\
	cd /usr/local/go/src; \
	./make.bash; \
	\
	export PATH="/usr/local/go/bin:$PATH"; \
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

# install "zip" (useful for handling AARs and JARs manually)
RUN apt-get install -y --no-install-recommends zip

# cleanup
RUN rm -rf /var/lib/apt/lists/*
