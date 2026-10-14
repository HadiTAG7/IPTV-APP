#!/usr/bin/env bash
# Generates small, legal synthetic test media into test/media/ (gitignored).
#
#   bash tool/gen_media.sh [--force]
#
# Sources are ffmpeg's own test patterns (testsrc2) and sine tones, so the
# output carries no third-party content. Existing files are kept unless
# --force is given. The fake panel (test/support/fake_panel.dart) serves:
#   h264_aac.ts  default live stream      h264_mp2.ts  stream 1002
#   h264_ac3.ts  stream 1003              hevc_aac.ts  stream 1004
#   vod_2audio_ara_eng_srt.mkv            every movie and episode
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/test/media"
force=0
for arg in "$@"; do
  case "$arg" in
    --force) force=1 ;;
    -h | --help)
      sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 64
      ;;
  esac
done

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg not found; install it (apt-get install -y ffmpeg)" >&2
  exit 1
fi

mkdir -p "$out"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

ff=(ffmpeg -hide_banner -loglevel error -nostdin -y)

# 20 s, 720p25, ~0.6 Mbit/s video with a 2 s GOP so HLS cuts find keyframes.
video_720p=(
  -f lavfi -i "testsrc2=size=1280x720:rate=25"
  -f lavfi -i "sine=frequency=440:beep_factor=4:sample_rate=48000"
)
x264_live=(
  -c:v libx264 -preset veryfast -profile:v main -pix_fmt yuv420p
  -b:v 600k -maxrate 600k -bufsize 1200k -g 50 -keyint_min 50 -sc_threshold 0
)
# One audio frame per PES lets the fake panel compute an exact loop length.
ts_opts=(
  -metadata service_provider="Fake Panel" -metadata service_name="Synthetic Test"
  -pes_payload_size 0 -f mpegts
)

# make <name> <ffmpeg args...>: writes atomically, skips existing files.
make() {
  local name="$1"
  shift
  local dest="$out/$name"
  if [[ -s "$dest" && $force -eq 0 ]]; then
    echo "skip   $name (exists)"
    return 0
  fi
  "${ff[@]}" "$@" "$tmp/$name.part"
  mv -f "$tmp/$name.part" "$dest"
  echo "wrote  $name ($(du -h "$dest" | cut -f1))"
}

encoders="$(ffmpeg -hide_banner -encoders 2>/dev/null || true)"
has_encoder() {
  grep -q " $1 " <<<"$encoders"
}

live_ts() {
  local name="$1" audio_codec="$2" audio_rate="$3"
  make "$name" "${video_720p[@]}" -t 20 -map 0:v -map 1:a \
    "${x264_live[@]}" -c:a "$audio_codec" -b:a "$audio_rate" -ac 2 \
    "${ts_opts[@]}"
}

live_ts h264_aac.ts aac 64k
live_ts h264_mp2.ts mp2 128k
live_ts h264_ac3.ts ac3 128k

if has_encoder libx265; then
  make hevc_aac.ts "${video_720p[@]}" -t 20 -map 0:v -map 1:a \
    -c:v libx265 -preset ultrafast -pix_fmt yuv420p -b:v 500k \
    -x265-params "log-level=error:keyint=50:min-keyint=50:scenecut=0" \
    -c:a aac -b:a 64k -ac 2 "${ts_opts[@]}"
else
  echo "skip   hevc_aac.ts (ffmpeg has no libx265 encoder)"
fi

# 60 s VOD: two audio tracks (ara, eng) and an Arabic SRT subtitle track.
cat >"$tmp/ara.srt" <<'SRT'
1
00:00:01,000 --> 00:00:05,000
مرحباً، هذا ملف اختبار اصطناعي.

2
00:00:20,000 --> 00:00:24,000
الترجمة العربية تعمل بشكل صحيح.

3
00:00:40,000 --> 00:00:44,000
نهاية المقطع التجريبي قريباً.
SRT

make vod_2audio_ara_eng_srt.mkv \
  -f lavfi -i "testsrc2=size=640x360:rate=25" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000" \
  -f lavfi -i "sine=frequency=880:sample_rate=48000" \
  -i "$tmp/ara.srt" \
  -t 60 -map 0:v -map 1:a -map 2:a -map 3:s \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -b:v 250k -g 50 \
  -c:a aac -b:a 64k -ac 2 -c:s srt \
  -metadata title="Synthetic VOD" \
  -metadata:s:a:0 language=ara -metadata:s:a:0 title="العربية" \
  -metadata:s:a:1 language=eng -metadata:s:a:1 title="English" \
  -metadata:s:s:0 language=ara -metadata:s:s:0 title="العربية" \
  -disposition:a:0 default -disposition:a:1 0 -disposition:s:0 0 \
  -f matroska

echo "media in $out"
