
#!/usr/bin/env bash
set -Eeuo pipefail

# Remove borders matching the image's corner colour.
# Usage: remove-black-bars.sh IMAGE [OUTPUT]

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 IMAGE [OUTPUT]" >&2
    exit 2
fi

input=$(realpath -- "$1")
[[ -f "$input" ]] || { echo "File not found: $input" >&2; exit 1; }

command -v magick >/dev/null || {
    echo "Install ImageMagick: sudo pacman -S imagemagick" >&2
    exit 1
}

if [[ $# -eq 2 ]]; then
    output=$2
else
    output="$(dirname -- "$input")/$(basename -- "${input%.*}")-cropped.${input##*.}"
fi

if [[ -e "$output" ]]; then
    echo "Output already exists: $output" >&2
    exit 1
fi

# Trim borders matching the top-left pixel, with a small colour tolerance.
tmp=$(mktemp --suffix=".${output##*.}" --tmpdir="$(dirname -- "$output")")
trap 'rm -f -- "$tmp"' EXIT

magick "$input" -fuzz 8% -trim +repage "$tmp"

# Refuse to save an empty or invalid result.
if ! magick identify "$tmp" >/dev/null 2>&1; then
    echo "Image processing failed." >&2
    exit 1
fi

mv -- "$tmp" "$output"
trap - EXIT

echo "Saved cropped image: $output"
