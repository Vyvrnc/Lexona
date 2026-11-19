#!/usr/bin/env bash
# chromium-drm-install.sh: Debian's Chromium with Google's Widevine CDM, for DRM video (Netflix,
# Disney+, HBO Max, Prime Video). Runs in Debian as (fake) root: env DD_NATIVE=0 debian-run.
#
# Widevine comes from AsahiLinux/widevine-installer (MIT, pinned commit): it downloads the arm64
# CDM from Google's ChromeOS image and fixes it up for glibc. The CDM is proprietary software of
# Google; installing it from the catalog is the user's acceptance of its licence (printed below).
# Only software decryption (Widevine L3): services cap the resolution, some refuse it
# (SkyShowtime: OVP_00114). Verified on the Galaxy Z Fold 7, 2026-11-19 (Gitea #15).
#
# Lines "chromium-drm: [n/N] ..." are progress for the app; "chromium-drm: ERROR: ..." the error.
set -u
INSTALLER_COMMIT=eab8c668ad3f9db27a444ee1f94b82d8f3ab5336
STEPS=4
say() { printf 'chromium-drm: %s\n' "$*"; }
step() { say "[$1/$STEPS] $2"; }
die() { say "ERROR: $*"; exit 1; }

[ "$(id -u)" = 0 ] || die "needs Debian's root (run with DD_NATIVE=0 debian-run)"
export DEBIAN_FRONTEND=noninteractive

step 1 "Installing Chromium from Debian"
apt-get install -y -o DPkg::Lock::Timeout=300 chromium squashfs-tools python3 curl ca-certificates ||
    { apt-get update && apt-get install -y -o DPkg::Lock::Timeout=300 chromium squashfs-tools python3 curl ca-certificates; } ||
    die "apt-get could not install Chromium (see the log)"

step 2 "Downloading widevine-installer"
work=$(mktemp -d "${TMPDIR:-/tmp}/chromium-drm.XXXXXX") || die "no temporary directory"
trap 'rm -rf "$work"' EXIT
curl -fsSL "https://github.com/AsahiLinux/widevine-installer/archive/$INSTALLER_COMMIT.tar.gz" | tar -xz -C "$work" ||
    die "could not download widevine-installer"
src=$work/widevine-installer-$INSTALLER_COMMIT

step 3 "Downloading and installing Widevine from Google (about 200 MB)"
# COPY_CONFIGS=0: its config step writes Fedora paths; Chromium's link is made below. The two
# "press Enter" prompts get their Enter here.
printf '\n\n' | env COPY_CONFIGS=0 TMPDIR="$work" sh "$src/widevine-installer" ||
    die "widevine-installer failed (see the log)"
[ -f /var/lib/widevine/libwidevinecdm.so ] || die "the Widevine CDM is missing after the install"

step 4 "Connecting Widevine to Chromium"
ln -sfn /var/lib/widevine/WidevineCdm /usr/lib/chromium/WidevineCdm || die "could not link WidevineCdm"
say "done: Chromium (DRM video) is in the menu"
