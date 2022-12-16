# Android section of this Dockerfile from https://medium.com/@elye.project/intro-to-docker-building-android-app-cb7fb1b97602
FROM openjdk:11

ENV SDK_URL="https://dl.google.com/android/repository/commandlinetools-linux-9123335_latest.zip" \
    ANDROID_HOME="/usr/local/android-sdk" \
    ANDROID_SDK=$ANDROID_HOME \
    ANDROID_VERSION=33 \
    ANDROID_BUILD_TOOLS_VERSION=33.0.0

## Download Android SDK
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
ENV NDK_VER="25.1.8937393"
RUN $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager "ndk;$NDK_VER"
RUN ln -sf $ANDROID_HOME/ndk/$NDK_VER $ANDROID_HOME/ndk-bundle

# Go section of this Dockerfile from Docker golang: https://github.com/docker-library/golang/blob/master/1.10/alpine3.8/Dockerfile
# Adapted from alpine apk to debian apt

## set up nsswitch.conf for Go's "netgo" implementation
## - https://github.com/golang/go/blob/go1.9.1/src/net/conf.go#L194-L275
## - docker run --rm debian:stretch grep '^hosts:' /etc/nsswitch.conf
RUN echo 'hosts: files dns' > /etc/nsswitch.conf

ENV GOLANG_VERSION=1.19.4
ENV GOLANG_SHA256=18ac263e39210bcf68d85f4370e97fb1734166995a1f63fb38b4f6e07d90d212

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		 bash \
		build-essential \
		openssl \
		libssl-dev \
		golang \
	; \
	rm -rf /var/lib/apt/lists/*; \
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
	wget -O go.tgz "https://golang.org/dl/go$GOLANG_VERSION.src.tar.gz"; \
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

# 2022.11.09
ENV GOMOBILEHASH=43a0384520996c8376bfb8637390f12b44773e65

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