# openjdk docker image version from https://hub.docker.com/_/openjdk : *stable* version (no 'ea' or 'rc'), using newest available debian base
FROM openjdk:20-jdk-bullseye

RUN apt-get update

# install "zip" (useful for handling AARs and JARs manually)
RUN apt-get install -y --no-install-recommends zip

# Android conf
## Command Line Tools url from https://developer.android.com/studio#command-line-tools-only
ENV SDK_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
ENV SDK_SHA256=2d2d50857e4eb553af5a6dc3ad507a17adf43d115264b1afc116f95c92e5e258
## Android version from the latest API in Android Studio
ENV ANDROID_VERSION=35
## Build Tools version from https://developer.android.com/tools/releases/build-tools#notes
ENV ANDROID_BUILD_TOOLS_VERSION=34.0.0
## NDK version from https://developer.android.com/ndk/downloads
ENV NDK_VER="27.2.12479018"

# GoLang conf
## Go version & hash from https://go.dev/dl/ (Hash from Archive Linux x86-64) : debian bullseye provides go1.15.15, which can only build go source up to go 1.19
ENV GOLANG_VERSION=1.23.5
ENV GOLANG_PREBUILT_SHA256=cbcad4a6482107c7c7926df1608106c189417163428200ce357695cc7e01d091
ENV GOLANG_SOURCE_SHA256=a6f3f4bbd3e6bdd626f79b668f212fbb5649daf75084fb79b678a0ae4d97423b
## GoMobile version from https://github.com/golang/mobile (Latest commit, as there is no tag yet)
ENV GOMOBILEHASH=c31d5b91ecc32c0d598b8fe8457d244ca0b4e815

## --- END OF VARIABLES TO CHANGE FOR UPDATE ---

# Android section of this Dockerfile from https://medium.com/@elye.project/intro-to-docker-building-android-app-cb7fb1b97602
## Download Android SDK
ENV ANDROID_HOME="/usr/local/android-sdk"
ENV ANDROID_SDK=$ANDROID_HOME
RUN mkdir "$ANDROID_HOME" .android \
    && mkdir -p $ANDROID_HOME/cmdline-tools/latest/ \
    && cd "$ANDROID_HOME" \
    && curl -o sdk-commandlinetools.zip $SDK_URL \
    && echo "$SDK_SHA256 sdk-commandlinetools.zip" | sha256sum -c - \
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
# Customized to bootstrap with the pre-buit binary, then build custom version from source which includes https://go-review.googlesource.com/c/go/+/408395

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

RUN set -eux; \
	arch="$(dpkg --print-architecture)"; arch="${arch##*-}"; \
	url=; \
	case "$arch" in \
		'amd64') \
			url_prebuilt="https://dl.google.com/go/go$GOLANG_VERSION.linux-amd64.tar.gz"; \
			url_src="https://dl.google.com/go/go$GOLANG_VERSION.src.tar.gz"; \
			;; \
		*) echo >&2 "error: unsupported architecture '$arch' (likely packaging update needed)"; exit 1 ;; \
	esac; \
	wget -O go_prebuilt.tgz.asc "$url_prebuilt.asc"; \
	wget -O go_prebuilt.tgz "$url_prebuilt" --progress=dot:giga; \
	wget -O go_src.tgz.asc "$url_src.asc"; \
	wget -O go_src.tgz "$url_src" --progress=dot:giga;

RUN	echo "$GOLANG_PREBUILT_SHA256 go_prebuilt.tgz" | sha256sum -c -;
RUN	echo "$GOLANG_SOURCE_SHA256 go_src.tgz" | sha256sum -c -;

ADD custom-seald-build.diff /root/

RUN set -eux; \
# https://github.com/golang/go/issues/14739#issuecomment-324767697
	GNUPGHOME="$(mktemp -d)"; export GNUPGHOME; \
# https://www.google.com/linuxrepositories/
	gpg --batch --keyserver keyserver.ubuntu.com --recv-keys 'EB4C 1BFD 4F04 2F6D DDCC  EC91 7721 F63B D38B 4796'; \
# let's also fetch the specific subkey of that key explicitly that we expect "go.tgz.asc" to be signed by, just to make sure we definitely have it
	gpg --batch --keyserver keyserver.ubuntu.com --recv-keys '2F52 8D36 D67B 69ED F998  D857 78BD 6547 3CB3 BD13'; \
	gpg --batch --verify go_prebuilt.tgz.asc go_prebuilt.tgz; \
	gpg --batch --verify go_src.tgz.asc go_src.tgz; \
	gpgconf --kill all; \
	rm -rf "$GNUPGHOME" go_prebuilt.tgz.asc go_src.tgz.asc; \
	\
	tar -C /usr/local -xzf go_prebuilt.tgz; \
	rm go_prebuilt.tgz; \
	\
	mv /usr/local/go /usr/local/go_prebuilt; \
	export PATH=/usr/local/go_prebuilt/bin:$PATH; \
	go version; \
    \
	tar -C /usr/local -xzf go_src.tgz; \
	rm go_src.tgz; \
    cd /usr/local/go; \
    git apply --reject /root/custom-seald-build.diff; \
    cd src; \
    ./all.bash; \
    rm -r /usr/local/go_prebuilt /root/custom-seald-build.diff

# persist new go in PATH
ENV PATH=/usr/local/go/bin:$PATH

RUN go version | grep "custom-seald-build"

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
