#!/bin/sh
# Films a reel of the game for TikTok / Reels / Shorts (src/capture.lua) and
# leaves it in capture/<reel>.mp4. `./capture.sh` shoots the boss montage;
# `./capture.sh <reel>` shoots another row of REELS.
#
# Everything it needs is LOVE 11, ffmpeg and -- on a machine with no screen,
# like a cloud session -- Xvfb. Whatever is missing is installed with apt where
# there is apt, so a fresh container can shoot with this one line and nothing
# set up beforehand; anywhere else it says what to install.
set -e
cd "$(dirname "$0")"
reel=${1:-montage}

need() { command -v "$1" >/dev/null 2>&1; }

missing=""
need love || missing="$missing love"
need ffmpeg || missing="$missing ffmpeg"
[ -n "$DISPLAY" ] || need xvfb-run || missing="$missing xvfb"

if [ -n "$missing" ]; then
    if need apt-get; then
        sudo=""
        [ "$(id -u)" -eq 0 ] || sudo="sudo"
        echo "capture.sh: installing$missing"
        $sudo apt-get update -qq >/dev/null 2>&1 || true
        # LOVE's package can report a post-install error in a container with no
        # sound card and still leave a working binary, so the check below is
        # what counts, not apt's exit code.
        DEBIAN_FRONTEND=noninteractive $sudo apt-get install -y -qq $missing >/dev/null 2>&1 || true
    fi
    for tool in love ffmpeg; do
        need "$tool" || { echo "capture.sh: $tool is not installed"; exit 1; }
    done
fi

if [ -n "$DISPLAY" ]; then
    love . --capture "$reel"
else
    need xvfb-run || { echo "capture.sh: no screen and no xvfb-run"; exit 1; }
    SDL_AUDIODRIVER=dummy xvfb-run -a love . --capture "$reel" 2>&1 | grep -v -e '^ALSA' -e 'Could not open device'
fi
