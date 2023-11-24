# openjdk docker image version from https://hub.docker.com/_/openjdk : *stable* version (no 'ea' or 'rc'), using newest available debian base
FROM openjdk:20-jdk-bullseye

RUN apt-get update

# install "zip" (useful for handling AARs and JARs manually)
RUN apt-get install -y --no-install-recommends zip

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
ENV GOLANG_VERSION=1.21.4
ENV GOLANG_SHA256=47b26a83d2b65a3c1c1bcace273b69bee49a7a7b5168a7604ded3d26a37bd787
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

ENV PATH /usr/local/go/bin:$PATH
RUN set -eux; \
	arch="$(dpkg --print-architecture)"; arch="${arch##*-}"; \
	url=; \
	case "$arch" in \
		'amd64') \
			url='https://dl.google.com/go/go$GOLANG_VERSION.linux-amd64.tar.gz'; \
			sha256='73cac0215254d0c7d1241fa40837851f3b9a8a742d0b54714cbdfb3feaf8f0af'; \
			;; \
		'armel') \
			export GOARCH='arm' GOARM='5' GOOS='linux'; \
			;; \
		'armhf') \
			url='https://dl.google.com/go/go$GOLANG_VERSION.linux-armv6l.tar.gz'; \
			sha256='6c62e89113750cc77c498194d13a03fadfda22bd2c7d44e8a826fd354db60252'; \
			;; \
		'arm64') \
			url='https://dl.google.com/go/go$GOLANG_VERSION.linux-arm64.tar.gz'; \
			sha256='ce1983a7289856c3a918e1fd26d41e072cc39f928adfb11ba1896440849b95da'; \
			;; \
		'i386') \
			url='https://dl.google.com/go/go$GOLANG_VERSION.linux-386.tar.gz'; \
			sha256='64d3e5d295806e137c9e39d1e1f10b00a30fcd5c2f230d72b3298f579bb3c89a'; \
			;; \
		'mips64el') \
			url='https://dl.google.com/go/go$GOLANG_VERSION.linux-mips64le.tar.gz'; \
			sha256='c7ce3a9dcf03322b79beda474c4a0154393d9029b48f7c2e260fb3365c8a6ad3'; \
			;; \
		'ppc64el') \
			url='https://dl.google.com/go/go$GOLANG_VERSION.linux-ppc64le.tar.gz'; \
			sha256='2c63b36d2adcfb22013102a2ee730f058ec2f93b9f27479793c80b2e3641783f'; \
			;; \
		'riscv64') \
			url='https://dl.google.com/go/go$GOLANG_VERSION.linux-riscv64.tar.gz'; \
			sha256='9695edd2109544b364daddb32816f5c7980f1f48b8490c51fa2c167f5b2eca48'; \
			;; \
		's390x') \
			url='https://dl.google.com/go/go$GOLANG_VERSION.linux-s390x.tar.gz'; \
			sha256='7a75ba4afc7a96058ca65903d994cd862381825d7dca12b2183f087c757c26c0'; \
			;; \
		*) echo >&2 "error: unsupported architecture '$arch' (likely packaging update needed)"; exit 1 ;; \
	esac; \
	build=; \
	if [ -z "$url" ]; then \
# https://github.com/golang/go/issues/38536#issuecomment-616897960
		build=1; \
		url='https://dl.google.com/go/go$GOLANG_VERSION.src.tar.gz'; \
		sha256='47b26a83d2b65a3c1c1bcace273b69bee49a7a7b5168a7604ded3d26a37bd787'; \
		echo >&2; \
		echo >&2 "warning: current architecture ($arch) does not have a compatible Go binary release; will be building from source"; \
		echo >&2; \
	fi; \
	\
	wget -O go.tgz.asc "$url.asc"; \
	wget -O go.tgz "$url" --progress=dot:giga; \
	echo "$sha256 *go.tgz" | sha256sum -c -; \
	\
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
	if [ -n "$build" ]; then \
		savedAptMark="$(apt-mark showmanual)"; \
# add backports for newer go version for bootstrap build: https://github.com/golang/go/issues/44505
		( \
			. /etc/os-release; \
			echo "deb https://deb.debian.org/debian $VERSION_CODENAME-backports main" > /etc/apt/sources.list.d/backports.list; \
			\
			apt-get update; \
			apt-get install -y --no-install-recommends -t "$VERSION_CODENAME-backports" golang-go; \
		); \
		\
		export GOCACHE='/tmp/gocache'; \
		\
		( \
			cd /usr/local/go/src; \
# set GOROOT_BOOTSTRAP + GOHOST* such that we can build Go successfully
			export GOROOT_BOOTSTRAP="$(go env GOROOT)" GOHOSTOS="$GOOS" GOHOSTARCH="$GOARCH"; \
			./make.bash; \
		); \
		\
		apt-mark auto '.*' > /dev/null; \
		apt-mark manual $savedAptMark > /dev/null; \
		apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
		rm -rf /var/lib/apt/lists/*; \
		\
# remove a few intermediate / bootstrapping files the official binary release tarballs do not contain
		rm -rf \
			/usr/local/go/pkg/*/cmd \
			/usr/local/go/pkg/bootstrap \
			/usr/local/go/pkg/obj \
			/usr/local/go/pkg/tool/*/api \
			/usr/local/go/pkg/tool/*/go_bootstrap \
			/usr/local/go/src/cmd/dist/dist \
			"$GOCACHE" \
		; \
	fi; \
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
