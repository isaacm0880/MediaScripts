#!/usr/bin/env bash
# Install MediaScripts for the current user. No root privileges required.
set -Eeuo pipefail
usage() { cat <<'EOF'
Usage: ./install.sh [--prefix DIRECTORY]
Default: ~/.local/opt/media-tools
Installs scripts and KDE launchers for the current user.
EOF
}
prefix="${HOME}/.local/opt/media-tools"
while (($#)); do
  case "$1" in
    --prefix|-p) (($# >= 2)) || { echo "Missing path" >&2; exit 2; }; prefix=$2; shift 2 ;;
    --prefix=*) prefix=${1#*=}; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ $EUID != 0 ]] || { echo "Run as your normal desktop user, not root." >&2; exit 1; }
src=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
[[ -f "$src/lib/common.sh" && -f "$src/bin/resolve-convert" ]] || { echo "Run this from a complete MediaScripts checkout." >&2; exit 1; }
mkdir -p -- "$prefix"
prefix=$(cd -- "$prefix" && pwd -P)
[[ $prefix != "$src" ]] || { echo "Install prefix must differ from repository directory." >&2; exit 1; }
for c in cp chmod python3 grep; do command -v "$c" >/dev/null || { echo "Missing command: $c" >&2; exit 1; }; done
service_dir="${XDG_DATA_HOME:-$HOME/.local/share}/kio/servicemenus"
app_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p -- "$service_dir" "$app_dir"
stamp=$(date +%Y%m%d-%H%M%S)
backup="$prefix/.install-backups/$stamp"
# Backup only paths we manage, without deleting unrelated user files.
for rel in bin/image-to-png bin/resolve-convert bin/video-remove-borders bin/image-remove-borders bin/audio-extract-cover bin/audio-extract-square-cover bin/img2png bin/resolve-prep bin/crop-bars bin/remove-black-bars bin/extract-audio-artwork bin/extract-square-thumbnail bin/resolve-keyboard-fix lib/common.sh lib/run-tests.sh README.md; do
  if [[ -e "$prefix/$rel" ]]; then
    mkdir -p -- "$backup/$(dirname "$rel")"
    cp -a -- "$prefix/$rel" "$backup/$rel"
  fi
done
for dir in bin lib; do
  mkdir -p -- "$prefix/$dir"
  cp -a -- "$src/$dir/." "$prefix/$dir/"
done
cp -- "$src/README.md" "$prefix/README.md"
chmod +x "$prefix"/bin/* "$prefix/lib/run-tests.sh"
mkdir -p -- "$prefix/conf examples"
cp -a -- "$src/conf examples/." "$prefix/conf examples/"
# Desktop files use literal hardcoded paths in the source; replace on installation.
old='/home/isaac/Custom/Scripts/media-tools'
for file in "$src"/desktops/*.desktop "$src"/launchers/*.desktop; do
  [[ -f "$file" ]] || continue
  name=$(basename "$file")
  if [[ $file == "$src"/desktops/* ]]; then dest="$service_dir/$name"; else dest="$app_dir/$name"; fi
  if [[ -e "$dest" ]]; then
    mkdir -p -- "$backup/kde"
    cp -a -- "$dest" "$backup/kde/$name"
  fi
  # Replace path without sed delimiter/escaping pitfalls.
  PREFIX="$prefix" OLD="$old" python3 - "$file" "$dest" <<'PY'
import os, pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
path = os.environ["PREFIX"]
# KDE Exec uses shell-like argument syntax: quote paths containing whitespace.
if any(ch in path for ch in '\n\r"\\'):
    raise SystemExit("Install path must not contain quotes or newlines")
source = source.replace(os.environ["OLD"], path.replace(' ', '\\ '))
pathlib.Path(sys.argv[2]).write_text(source)
PY
  chmod +x "$dest"
done
# Retire only known obsolete desktop entry filenames from previous installs.
for oldname in media-tools-img2png.desktop media-tools-resolve-prep.desktop media-tools-crop-bars.desktop media-tools-remove-black-bars.desktop media-tools-extract-audio-artwork.desktop media-tools-extract-square-thumbnail.desktop; do
  if [[ -f "$service_dir/$oldname" ]] && grep -Fq "/bin/" "$service_dir/$oldname"; then
    mkdir -p -- "$backup/kde/retired"
    mv -- "$service_dir/$oldname" "$backup/kde/retired/$oldname"
  fi
done
for oldname in media-tools-img2png-launcher.desktop media-tools-resolve-prep-launcher.desktop media-tools-crop-bars-launcher.desktop; do
  if [[ -f "$app_dir/$oldname" ]] && grep -Fq "$old/bin/" "$app_dir/$oldname"; then
    mkdir -p -- "$backup/kde/retired"
    mv -- "$app_dir/$oldname" "$backup/kde/retired/$oldname"
  fi
done
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 >/dev/null 2>&1 || true
printf 'Installed MediaScripts: %s\nDolphin menus: %s\nApplication launchers: %s\n' "$prefix" "$service_dir" "$app_dir"
[[ -d $backup ]] && printf 'Previous files backed up: %s\n' "$backup"
echo 'Restart Dolphin if the new right-click entries do not appear.'
