#!/usr/bin/env bash
# Installs the dev toolchain on a Debian/Ubuntu box. Idempotent: re-running skips what is present.
# Usage: scripts/bootstrap.sh [--android]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS_BIN="$HOME/.local/bin"
FLUTTER_DIR="${FLUTTER_DIR:-$HOME/flutter}"
ANDROID_SDK="${ANDROID_HOME:-$HOME/android-sdk}"
WITH_ANDROID=0
[[ "${1:-}" == "--android" ]] && WITH_ANDROID=1

mkdir -p "$TOOLS_BIN"
arch_go() { case "$(uname -m)" in x86_64) echo amd64 ;; aarch64|arm64) echo arm64 ;; *) uname -m ;; esac; }
latest_tag() { curl -fsSI "https://github.com/$1/releases/latest" | sed -n 's#^location: .*/tag/\(.*\)\r#\1#Ip'; }
log() { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }

log "apt packages"
sudo apt-get update -qq || log "apt-get update failed (mirror?); continuing with cached package lists"
sudo apt-get install -y -qq curl git unzip xz-utils zip jq ca-certificates docker.io >/dev/null

log "docker"
# Containers (no systemd) need dockerd started directly; /var/run may be a 0700 dir rather than a symlink to /run.
if ! sudo docker info >/dev/null 2>&1; then
  sudo systemctl enable --now docker >/dev/null 2>&1 || sudo service docker start >/dev/null 2>&1 || true
  for _ in $(seq 30); do sudo docker info >/dev/null 2>&1 && break; sleep 1; done
fi
id -nG "$USER" | grep -qw docker || sudo usermod -aG docker "$USER"
[[ -L /var/run ]] || sudo chmod 755 /var/run
# The group change needs a new login; open the socket so this session and agents can use it now.
sudo chmod 666 /var/run/docker.sock
docker info >/dev/null

# Stale iptables-legacy rules from an earlier Docker on this image set FORWARD to DROP and
# silently block traffic between containers on user-defined bridges (Supabase's network).
if command -v iptables-legacy >/dev/null && sudo iptables-legacy -L DOCKER-USER -n >/dev/null 2>&1; then
  for dir in -i -o; do
    sudo iptables-legacy -C DOCKER-USER "$dir" br-+ -j ACCEPT 2>/dev/null \
      || sudo iptables-legacy -I DOCKER-USER "$dir" br-+ -j ACCEPT
  done
fi

log "supabase cli"
if ! command -v supabase >/dev/null; then
  tag="$(latest_tag supabase/cli)"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/supabase.deb" "https://github.com/supabase/cli/releases/download/${tag}/supabase_${tag#v}_linux_$(arch_go).deb"
  sudo dpkg -i "$tmp/supabase.deb" >/dev/null
  rm -rf "$tmp"
fi
supabase --version

log "gitleaks"
if ! command -v gitleaks >/dev/null; then
  tag="$(latest_tag gitleaks/gitleaks)"
  arch="$(uname -m)"; [[ "$arch" == "aarch64" ]] && arch=arm64; [[ "$arch" == "x86_64" ]] && arch=x64
  curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/${tag}/gitleaks_${tag#v}_linux_${arch}.tar.gz" | tar -xz -C "$TOOLS_BIN" gitleaks
fi
"$TOOLS_BIN/gitleaks" version 2>/dev/null || gitleaks version

log "deno"
if ! command -v deno >/dev/null && [[ ! -x "$HOME/.deno/bin/deno" ]]; then
  curl -fsSL https://deno.land/install.sh | sh -s -- -y --no-modify-path >/dev/null
fi
"$HOME/.deno/bin/deno" --version | head -1 2>/dev/null || deno --version | head -1

log "flutter (stable)"
if [[ ! -x "$FLUTTER_DIR/bin/flutter" ]]; then
  archive="$(curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json \
    | jq -r '.current_release.stable as $h | .releases[] | select(.hash==$h) | .archive')"
  curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/$archive" | tar -xJ -C "$(dirname "$FLUTTER_DIR")"
fi
git config --global --add safe.directory "$FLUTTER_DIR" 2>/dev/null || true
"$FLUTTER_DIR/bin/flutter" config --no-analytics --enable-web >/dev/null
"$FLUTTER_DIR/bin/flutter" --version | head -1

if [[ $WITH_ANDROID == 1 ]]; then
  log "android sdk (cmdline tools + platform + build tools)"
  sudo apt-get install -y -qq openjdk-21-jdk-headless >/dev/null
  if [[ ! -x "$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager" ]]; then
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/clt.zip" https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip
    mkdir -p "$ANDROID_SDK/cmdline-tools"
    unzip -q "$tmp/clt.zip" -d "$tmp" && mv "$tmp/cmdline-tools" "$ANDROID_SDK/cmdline-tools/latest"
    rm -rf "$tmp"
  fi
  yes | "$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null || true
  "$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager" "platform-tools" "platforms;android-36" "build-tools;36.0.0" >/dev/null
  "$FLUTTER_DIR/bin/flutter" config --android-sdk "$ANDROID_SDK" >/dev/null
fi

log "playwright (e2e/)"
(cd "$REPO_ROOT/e2e" && npm ci --silent && npx playwright install --with-deps chromium >/dev/null)

log "git hooks"
git -C "$REPO_ROOT" config core.hooksPath .githooks

cat <<EOF

Done. Add to your shell profile if missing:
  export PATH="$FLUTTER_DIR/bin:\$HOME/.deno/bin:$TOOLS_BIN:\$PATH"
EOF
