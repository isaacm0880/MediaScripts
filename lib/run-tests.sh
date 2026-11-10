#!/usr/bin/env bash
# Self-contained smoke tests. Creates synthetic media in a temp dir (never touches your files).
# Run:  bash tests/run-tests.sh      (needs ffmpeg; image tests need imagemagick + file)
set -u
ROOT=$(dirname "$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")")
B=$ROOT/bin; W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; cd "$W" || exit 1
pass=0; fail=0
ok()  { echo "PASS  $1"; ((pass++)); }
bad() { echo "FAIL  $1"; ((fail++)); }
chk() { local d=$1; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }
ff()  { ffmpeg -v error -y "$@"; }
V="testsrc2=size=320x180:rate=25:duration=12"

ff -f lavfi -i "$V" -f lavfi -i sine=duration=12 -c:v libx264 -pix_fmt yuv420p -c:a aac "my clip (aac).mp4"
ff -f lavfi -i "$V" -f lavfi -i sine=duration=12 -c:v libx264 -pix_fmt yuv420p -c:a pcm_s16le good.mov
ff -f lavfi -i "$V" -f lavfi -i sine=duration=12 -c:v libvpx-vp9 -c:a libopus clip.webm
ff -f lavfi -i "$V" -vf "pad=320:240:0:30:black" -c:v libx264 -pix_fmt yuv420p "letter box.mp4"
ff -f lavfi -i "$V" -c:v libx264 -pix_fmt yuv420p nobars.mp4
echo junk > "not media.mp4"

echo "--- resolve-convert"
out=$(bash "$B/resolve-convert" --audio-only -n "my clip (aac).mp4" 2>&1)
chk "audio-only: audio CONVERT to PCM"  grep -q "CONVERT -> pcm_s16le" <<<"$out"
chk "audio-only: video planned as COPY" grep -q "Video #0: *COPY unchanged" <<<"$out"
bash "$B/resolve-convert" --audio-only --yes "my clip (aac).mp4" >/dev/null 2>&1 </dev/null
chk "output .mov exists"              test -f "my clip (aac) - Resolve.mov"
chk "output audio is PCM"             test "$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "my clip (aac) - Resolve.mov")" = pcm_s16le
chk "output video still h264 (copied)" test "$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "my clip (aac) - Resolve.mov")" = h264
before=$(md5sum "my clip (aac).mp4")
bash "$B/resolve-convert" --audio-only --yes "my clip (aac).mp4" >/dev/null 2>&1 </dev/null
chk "second run does not overwrite"   test "$(ls | grep -c 'my clip (aac) - Resolve')" -ge 2
chk "original unchanged"              test "$(md5sum "my clip (aac).mp4")" = "$before"
out=$(bash "$B/resolve-convert" --analyze good.mov 2>&1 </dev/null)
chk "PCM+h264 mov: analyse says none" grep -q "no conversion needed" <<<"$out"
out=$(bash "$B/resolve-convert" --analyze clip.webm 2>&1 </dev/null)
chk "vp9 webm -> analyse recommends both" grep -q "Recommended: BOTH" <<<"$out"
out=$(bash "$B/resolve-convert" --audio-only --container mkv -n clip.webm 2>&1 </dev/null)
chk "audio-only keeps vp9 video as COPY + warns" grep -q "COPIED UNCHANGED" <<<"$out"
bash "$B/resolve-convert" "good.mov" </dev/null >/dev/null 2>&1; chk "no mode + no terminal -> exit 2" test $? -eq 2
out=$(bash "$B/resolve-convert" --video-only -n "my clip (aac).mp4" 2>&1 </dev/null)
chk "video-only copies AAC audio" grep -q "COPY unchanged   \[aac" <<<"$out"
bash "$B/resolve-convert" --video-only --yes clip.webm </dev/null >/dev/null 2>&1; chk "video-only + opus -> container conflict stops (exit 1)" test $? -eq 1
bash "$B/resolve-convert" --both -n "not media.mp4" nonexistent.mp4 >/dev/null 2>&1 </dev/null; chk "bad inputs -> exit 1" test $? -eq 1
PATH=/nonexistent "$(command -v bash)" "$B/resolve-convert" --analyze good.mov >/dev/null 2>&1; chk "missing ffmpeg -> exit 2" test $? -eq 2

echo "--- video-remove-borders"
out=$(bash "$B/video-remove-borders" --analyze "letter box.mp4" 2>&1)
chk "letterbox detected + validated"  grep -q "Result: VALIDATED" <<<"$out"
chk "crop is 320:184:0:28"            grep -q "crop=320:184:0:28" <<<"$out"
out=$(bash "$B/video-remove-borders" --analyze nobars.mp4 2>&1)
chk "no bars -> NONE"                 grep -q "Result: NONE" <<<"$out"
bash "$B/video-remove-borders" "letter box.mp4" >/dev/null 2>&1 </dev/null; chk "no confirmation -> exit 3, no output" test $? -eq 3
bash "$B/video-remove-borders" --yes --encoder x264 "letter box.mp4" >/dev/null 2>&1
chk "encoded file is 320x184" test "$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "letter box-cropped.mp4")" = 320x184
bash "$B/video-remove-borders" --crop 999:999:0:0 -a "letter box.mp4" >/dev/null 2>&1; chk "bad manual crop rejected" test $? -eq 1

echo "--- image-to-png (skipped if tools missing)"
if command -v magick >/dev/null && command -v file >/dev/null; then
  magick -size 20x20 xc:red "a b.jpg"; echo x > x.bin
  bash "$B/image-to-png" "a b.jpg" >/dev/null 2>&1; chk "jpg -> png" test -f "a b.png"
  bash "$B/image-to-png" "a b.jpg" >/dev/null 2>&1; chk "no overwrite (a b (2).png)" test -f "a b (2).png"
  bash "$B/image-to-png" x.bin >/dev/null 2>&1; chk "non-image -> exit 1" test $? -eq 1
else echo "SKIP  (needs imagemagick 7 'magick' and 'file')"; fi
echo; echo "passed: $pass  failed: $fail"; ((fail == 0))
