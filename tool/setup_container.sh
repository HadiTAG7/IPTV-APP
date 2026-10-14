#!/usr/bin/env bash
# Prepares a Linux x64 machine (dev container or CI-like VM) to build, test and
# package the app: Flutter 3.47.7, a JDK 17+ (Gradle and apksigner), the Android
# SDK (platform-tools, android-36, build-tools 36.0.0, NDK 28.2.13676358) and the
# Linux desktop/integration deps.
# Safe to re-run: every step skips what is already installed. Peak disk use is
# about 13-16 GB.
#
# Usage: bash tool/setup_container.sh
# Env:
#   SDK_DIR=~/sdk          where flutter/ and android/ are installed
#   SKIP_APT=1             skip apt packages (no root, or installed another way);
#                          a JDK 17+ must then already be on PATH
#   USE_CENTRAL_MIRROR=1   make Gradle use Google's Maven Central mirror
#                          (see "Maven Central 429" below)
#
# Afterwards, in every shell:
#   export PATH="$HOME/sdk/flutter/bin:$PATH" ANDROID_HOME="$HOME/sdk/android"
#
# Troubleshooting:
#   - pub/curl TLS errors behind an intercepting proxy:
#       export SSL_CERT_FILE=/path/to/proxy-ca-bundle.crt
#   - Maven Central 429 (Too Many Requests): shared proxies and CI IPs get rate
#     limited while Gradle resolves plugins. Re-run the Gradle build, or re-run
#     this script with USE_CENTRAL_MIRROR=1 to add ~/.gradle/init.d/central-mirror.gradle,
#     which rewrites repo.maven.apache.org to
#     https://maven-central.storage-download.googleapis.com/maven2/ for every build.
set -euo pipefail

FLUTTER_VERSION=3.47.7
FLUTTER_TARBALL=flutter_linux_${FLUTTER_VERSION}-stable.tar.xz
FLUTTER_URL=https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/$FLUTTER_TARBALL
FLUTTER_SHA256=af7455f540df951184c7953fbe3cf884766e7541dacf8571f9f582db03dd6230
CMDLINE_TOOLS_ZIP=commandlinetools-linux-16111833_latest.zip
CMDLINE_TOOLS_URL=https://dl.google.com/android/repository/$CMDLINE_TOOLS_ZIP
ANDROID_PACKAGES=(
  "platform-tools"
  "platforms;android-36"
  "build-tools;36.0.0"
  "ndk;28.2.13676358"
)
APT_PACKAGES=(
  curl git unzip xz-utils zip
  clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev
  libmpv-dev mpv ffmpeg xvfb
)
# Gradle 9 / AGP 9 and apksigner need Java 17+; installed only if PATH has no such java.
MIN_JAVA=17
JDK_APT_PACKAGE=openjdk-17-jdk-headless
CENTRAL_MIRROR=https://maven-central.storage-download.googleapis.com/maven2/

SDK_DIR=${SDK_DIR:-$HOME/sdk}
FLUTTER_DIR=$SDK_DIR/flutter
ANDROID_DIR=$SDK_DIR/android
SDKMANAGER=$ANDROID_DIR/cmdline-tools/latest/bin/sdkmanager

log() { printf '\n==> %s\n' "$*"; }

as_root() {
  if [[ $(id -u) -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

install_apt_packages() {
  if [[ "${SKIP_APT:-0}" == 1 ]]; then
    log "Skipping apt packages (SKIP_APT=1)"
    return
  fi
  if ! command -v apt-get >/dev/null; then
    log "apt-get not found; install these yourself: ${APT_PACKAGES[*]}"
    return
  fi
  local missing=() pkg
  for pkg in "${APT_PACKAGES[@]}"; do
    dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  if ((${#missing[@]} == 0)); then
    log "apt packages already installed"
    return
  fi
  log "Installing apt packages: ${missing[*]}"
  as_root apt-get update -q
  local available=()
  for pkg in "${missing[@]}"; do
    if apt-cache show "$pkg" >/dev/null 2>&1; then
      available+=("$pkg")
    else
      echo "warning: apt package $pkg is not available on this distribution; skipping" >&2
    fi
  done
  if ((${#available[@]} > 0)); then
    as_root env DEBIAN_FRONTEND=noninteractive \
      apt-get install -y -q --no-install-recommends "${available[@]}"
  fi
}

# java_major <java>: feature version (8 for 1.8.0_x, 17 for 17.0.2), or nothing.
java_major() {
  local v
  v=$("$1" -XshowSettings:properties -version 2>&1 |
    sed -nE 's/^ *java\.specification\.version = ([0-9.]+).*/\1/p' | head -n1) || true
  v=${v#1.}
  printf '%s' "${v%%.*}"
}

# java_home <java>: the JDK directory a java binary belongs to.
java_home() {
  "$1" -XshowSettings:properties -version 2>&1 |
    sed -nE 's/^ *java\.home = (.+)$/\1/p' | head -n1 || true
}

# java_ok <java>: true if it is an executable java of at least MIN_JAVA.
java_ok() {
  local major
  [[ -n "$1" && -x "$1" ]] || return 1
  major=$(java_major "$1")
  [[ -n "$major" ]] && ((major >= MIN_JAVA))
}

ensure_jdk() {
  if ! java_ok "$(command -v java || true)"; then
    if [[ "${SKIP_APT:-0}" != 1 ]] && command -v apt-get >/dev/null; then
      log "Installing $JDK_APT_PACKAGE (Gradle and apksigner need Java $MIN_JAVA+)"
      as_root apt-get update -q
      as_root env DEBIAN_FRONTEND=noninteractive \
        apt-get install -y -q --no-install-recommends "$JDK_APT_PACKAGE"
      hash -r
    fi
    if ! java_ok "$(command -v java || true)"; then
      echo "error: no Java $MIN_JAVA+ on PATH. Install a JDK (e.g. apt-get install $JDK_APT_PACKAGE), put its bin/ on PATH and re-run." >&2
      exit 1
    fi
  fi
  local java
  java=$(command -v java)
  log "Using Java $(java_major "$java") from $(java_home "$java")"
  # Flutter runs Gradle with JAVA_HOME when it is set; if that JDK is too old, pin
  # Flutter to the PATH one instead.
  if [[ -n "${JAVA_HOME:-}" ]] && ! java_ok "$JAVA_HOME/bin/java"; then
    log "JAVA_HOME=$JAVA_HOME is older than Java $MIN_JAVA; running flutter config --jdk-dir"
    flutter config --jdk-dir "$(java_home "$java")" >/dev/null
  fi
}

installed_flutter_version() {
  local info=$FLUTTER_DIR/bin/cache/flutter.version.json
  [[ -x "$FLUTTER_DIR/bin/flutter" ]] || return 0
  # A fresh checkout writes the version file on its first run.
  [[ -f "$info" ]] || "$FLUTTER_DIR/bin/flutter" --version >/dev/null 2>&1 || true
  [[ -f "$info" ]] || return 0
  sed -nE 's/.*"frameworkVersion": *"([^"]+)".*/\1/p' "$info" | head -n1
}

install_flutter() {
  if [[ "$(installed_flutter_version)" == "$FLUTTER_VERSION" ]]; then
    log "Flutter $FLUTTER_VERSION already installed in $FLUTTER_DIR"
  else
    if [[ -e "$FLUTTER_DIR" ]]; then
      echo "error: $FLUTTER_DIR exists but is not Flutter $FLUTTER_VERSION; move it away first" >&2
      exit 1
    fi
    log "Downloading Flutter $FLUTTER_VERSION"
    local tmp
    tmp=$(mktemp -d)
    curl -fL --retry 3 -o "$tmp/$FLUTTER_TARBALL" "$FLUTTER_URL"
    echo "$FLUTTER_SHA256  $tmp/$FLUTTER_TARBALL" | sha256sum -c -
    mkdir -p "$SDK_DIR"
    tar -xf "$tmp/$FLUTTER_TARBALL" -C "$SDK_DIR"
    rm -rf "$tmp"
  fi
  export PATH="$FLUTTER_DIR/bin:$PATH"
  # The tarball is a git checkout; root-owned containers trip git's ownership check.
  git config --global --get-all safe.directory | grep -qx "$FLUTTER_DIR" ||
    git config --global --add safe.directory "$FLUTTER_DIR"
  flutter config --no-analytics >/dev/null
  dart --disable-analytics >/dev/null 2>&1 || true
}

install_android_sdk() {
  if [[ -x "$SDKMANAGER" ]]; then
    log "Android cmdline-tools already installed"
  else
    log "Downloading Android cmdline-tools"
    local tmp
    tmp=$(mktemp -d)
    curl -fL --retry 3 -o "$tmp/$CMDLINE_TOOLS_ZIP" "$CMDLINE_TOOLS_URL"
    mkdir -p "$ANDROID_DIR/cmdline-tools"
    unzip -q "$tmp/$CMDLINE_TOOLS_ZIP" -d "$tmp"
    rm -rf "$ANDROID_DIR/cmdline-tools/latest"
    mv "$tmp/cmdline-tools" "$ANDROID_DIR/cmdline-tools/latest"
    rm -rf "$tmp"
  fi
  export ANDROID_HOME=$ANDROID_DIR
  log "Accepting licenses and installing Android packages"
  yes | "$SDKMANAGER" --sdk_root="$ANDROID_DIR" --licenses >/dev/null || true
  "$SDKMANAGER" --sdk_root="$ANDROID_DIR" "${ANDROID_PACKAGES[@]}"
  flutter config --android-sdk "$ANDROID_DIR" >/dev/null
}

configure_central_mirror() {
  local init=$HOME/.gradle/init.d/central-mirror.gradle
  if [[ "${USE_CENTRAL_MIRROR:-0}" != 1 ]]; then
    if [[ -f "$init" ]]; then log "Gradle Maven Central mirror is active ($init)"; fi
    return 0
  fi
  log "Writing $init"
  mkdir -p "$(dirname "$init")"
  cat >"$init" <<EOF
// Written by tool/setup_container.sh (USE_CENTRAL_MIRROR=1). Maven Central rate-limits
// some shared proxies (HTTP 429), so resolve it through Google's mirror instead.
def centralMirror = '$CENTRAL_MIRROR'
def rewrite = { repos ->
  repos.withType(MavenArtifactRepository).configureEach { r ->
    if (r.url.toString().startsWith('https://repo.maven.apache.org/maven2')) {
      r.url = centralMirror
    }
  }
}
beforeSettings { settings ->
  rewrite(settings.pluginManagement.repositories)
  rewrite(settings.dependencyResolutionManagement.repositories)
}
allprojects {
  rewrite(buildscript.repositories)
  rewrite(repositories)
}
EOF
}

main() {
  install_apt_packages
  install_flutter
  ensure_jdk
  install_android_sdk
  configure_central_mirror
  log "flutter doctor"
  flutter doctor -v || true
  cat <<EOF

Done. In each new shell run:
  export PATH="$FLUTTER_DIR/bin:\$PATH" ANDROID_HOME="$ANDROID_DIR"
Then, in the repo:
  flutter pub get && flutter test --exclude-tags network,bench
  flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 \\
    --build-name 0.0.0-dev --build-number 1 -P force-version-code-ignoring-abi=true
  bash tool/check_apk.sh build/app/outputs/flutter-apk/app-arm64-v8a-release.apk 90
EOF
}

# Run only when executed, so tests can source the helpers.
if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
  main "$@"
fi
