# shellcheck shell=bash
# common.sh - shared helpers for the media-tools scripts (img2png, resolve-prep,
# crop-bars).  This file is SOURCED, never executed.  Requires Bash >= 4.4.
#
# Nothing in here deletes or modifies user media.  The only files this library
# ever removes are temporary files/directories that the running script itself
# created through mktemp (tracked in MT_TMP_FILES / MT_TMP_DIRS).

MT_VERSION="1.0.0"

# ---------------------------------------------------------------- output ---
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
  MT_C_RED=$'\e[31m'; MT_C_YEL=$'\e[33m'; MT_C_GRN=$'\e[32m'
  MT_C_BLD=$'\e[1m';  MT_C_DIM=$'\e[2m';  MT_C_RST=$'\e[0m'
else
  MT_C_RED=''; MT_C_YEL=''; MT_C_GRN=''; MT_C_BLD=''; MT_C_DIM=''; MT_C_RST=''
fi

mt_info()   { printf '%s\n' "$*"; }
mt_ok()     { printf '%s%s%s\n' "$MT_C_GRN" "$*" "$MT_C_RST"; }
mt_warn()   { printf '%sWARNING:%s %s\n' "$MT_C_YEL" "$MT_C_RST" "$*" >&2; }
mt_err()    { printf '%sERROR:%s %s\n' "$MT_C_RED" "$MT_C_RST" "$*" >&2; }
mt_die()    { local code=$1; shift; mt_err "$*"; exit "$code"; }
mt_banner() { printf '\n%s== %s ==%s\n' "$MT_C_BLD" "$*" "$MT_C_RST"; }
mt_kv()     { printf '  %-14s %s\n' "$1" "$2"; }

# ---------------------------------------------------------- dependencies ---
MT_MISSING_CMDS=()
MT_MISSING_PKGS=()

# mt_need COMMAND ARCH_PACKAGE   - register a required command
mt_need() {
  command -v "$1" >/dev/null 2>&1 && return 0
  MT_MISSING_CMDS+=("$1")
  MT_MISSING_PKGS+=("$2")
}

# mt_deps_or_die - abort (exit 2) with an install hint if anything is missing
mt_deps_or_die() {
  ((${#MT_MISSING_CMDS[@]} == 0)) && return 0
  local -a pk
  mt_err "Missing required command(s): ${MT_MISSING_CMDS[*]}"
  mapfile -t pk < <(printf '%s\n' "${MT_MISSING_PKGS[@]}" | sort -u)
  mt_info "Install with:  sudo pacman -S ${pk[*]}"
  exit 2
}

# ---------------------------------------------------------------- config ---
# mt_load_config TOOL VAR...
# Sources ${XDG_CONFIG_HOME:-~/.config}/media-tools/TOOL.conf if it exists.
# Precedence is  CLI flag > environment variable > config file > built-in
# default: variables that were already set in the environment before the file
# is sourced are restored afterwards.
MT_CONFIG_USED=""
mt_load_config() {
  local tool=$1; shift
  local f="${XDG_CONFIG_HOME:-$HOME/.config}/media-tools/$tool.conf" v
  local -A saved=()
  [[ -r $f ]] || return 0
  for v in "$@"; do [[ -v $v ]] && saved[$v]=${!v}; done
  # shellcheck disable=SC1090
  source "$f"
  for v in "${!saved[@]}"; do printf -v "$v" '%s' "${saved[$v]}"; done
  MT_CONFIG_USED=$f
}

# ------------------------------------------------- temp files, traps, exit ---
MT_TMP_FILES=()
MT_TMP_DIRS=()
MT_PAUSE=${MT_PAUSE:-0}

mt_mktemp_file() {   # DIR -> prints path of new empty temp file (registered)
  local p
  p=$(mktemp --suffix=.partial -- "$1/.mt-XXXXXXXX") || return 1
  MT_TMP_FILES+=("$p"); printf '%s' "$p"
}
mt_mktemp_dir() {    # DIR -> prints path of new temp directory (registered)
  local p
  p=$(mktemp -d -- "$1/.mt-XXXXXXXX") || return 1
  MT_TMP_DIRS+=("$p"); printf '%s' "$p"
}
mt_cleanup_tmp() {
  local p
  for p in "${MT_TMP_FILES[@]}"; do [[ -n $p && -e $p ]] && rm -f -- "$p"; done
  for p in "${MT_TMP_DIRS[@]}";  do [[ -n $p && -d $p ]] && rm -rf -- "$p"; done
  MT_TMP_FILES=(); MT_TMP_DIRS=()
}
mt_exit_hook() {
  local rc=$?
  trap - EXIT
  mt_cleanup_tmp
  if [[ $MT_PAUSE == 1 && -t 0 ]]; then
    printf '\n%s(exit status %d)%s  Press Enter to close this window...' "$MT_C_DIM" "$rc" "$MT_C_RST"
    read -r _ || true
  fi
  exit "$rc"
}
mt_install_traps() {
  trap mt_exit_hook EXIT
  trap 'printf "\n" >&2; mt_err "Interrupted - temporary files removed, originals untouched."; exit 130' INT TERM HUP
}

# ----------------------------------------------------------------- paths ---
mt_stem() { local b=$1; if [[ $b == ?*.* ]]; then printf '%s' "${b%.*}"; else printf '%s' "$b"; fi; }
mt_ext()  { local b=$1; if [[ $b == ?*.* ]]; then local e=${b##*.}; printf '%s' "${e,,}"; fi; }

# mt_unique_path DIR STEM EXT STYLE
#   EXT includes the leading dot (or is empty).  STYLE: counter | stamp.
#   Prints a path that does not exist yet.  Never returns an existing path.
mt_unique_path() {
  local dir=$1 stem=$2 ext=$3 style=${4:-counter} p n=2 ts
  p="$dir/$stem$ext"
  if [[ ! -e $p && ! -L $p ]]; then printf '%s' "$p"; return 0; fi
  if [[ $style == stamp ]]; then
    ts=$(date '+%Y-%m-%d %H-%M-%S')
    stem="$stem $ts"
    p="$dir/$stem$ext"
    if [[ ! -e $p && ! -L $p ]]; then printf '%s' "$p"; return 0; fi
  fi
  while :; do
    p="$dir/$stem ($n)$ext"
    if [[ ! -e $p && ! -L $p ]]; then printf '%s' "$p"; return 0; fi
    ((n++))
  done
}

# mt_commit TMP FINAL - move TMP to FINAL without clobbering; 1 if FINAL exists.
mt_commit() {
  local tmp=$1 final=$2
  if [[ -e $final || -L $final ]]; then return 1; fi
  mv -n -- "$tmp" "$final" 2>/dev/null || return 1
  [[ ! -e $tmp ]]
}

# -------------------------------------------------------------- user I/O ---
# mt_confirm "question"  - y/N prompt; returns 1 when not interactive.
mt_confirm() {
  local ans
  [[ -t 0 ]] || return 1
  read -r -p "$1 [y/N] " ans || return 1
  [[ ${ans,,} == y || ${ans,,} == yes ]]
}

# mt_pick_files TITLE FILTER  - KDE file dialog; fills MT_PICKED.  1 = cancelled
MT_PICKED=()
mt_pick_files() {
  local out
  command -v kdialog >/dev/null 2>&1 || mt_die 2 "--pick needs kdialog (sudo pacman -S kdialog)."
  out=$(kdialog --title "$1" --multiple --separate-output \
        --getopenfilename "${HOME:-/}" "$2") || return 1
  [[ -n $out ]] || return 1
  mapfile -t MT_PICKED <<<"$out"
  ((${#MT_PICKED[@]} > 0))
}

# mt_in_list WORD "list of words"
mt_in_list() { [[ " $2 " == *" $1 "* ]]; }

# mt_lang_norm TAG - normalise common ISO-639-1/-2 language tags to 3 letters
mt_lang_norm() {
  local l=${1,,}
  case $l in
    en|eng|english)               echo eng ;;
    ja|jpn|japanese)              echo jpn ;;
    fr|fre|fra|french)            echo fra ;;
    de|ger|deu|german)            echo deu ;;
    es|spa|spanish)               echo spa ;;
    it|ita|italian)               echo ita ;;
    pt|por|portuguese)            echo por ;;
    ru|rus|russian)               echo rus ;;
    ko|kor|korean)                echo kor ;;
    zh|zho|chi|chinese)           echo zho ;;
    nl|dut|nld|dutch)             echo nld ;;
    sv|swe|swedish)               echo swe ;;
    pl|pol|polish)                echo pol ;;
    und|'')                       echo und ;;
    *)                            echo "$l" ;;
  esac
}

# mt_frac_to_num "30000/1001" -> 29.970
mt_frac_to_num() {
  awk -v f="$1" 'BEGIN{n=split(f,a,"/"); if(n==2 && a[2]+0!=0) printf "%.3f", a[1]/a[2]; else if(n==1 && f+0>0) printf "%.3f", f+0; else printf "0"}'
}

# mt_pix_chroma PIX_FMT -> 420|422|444|gray|""     mt_pix_depth PIX_FMT -> 8|10|12|...
mt_pix_chroma() {
  case $1 in
    yuv420p*|yuvj420p|nv12|nv21|p010*|p016*|p012*) echo 420 ;;
    yuv422p*|yuvj422p|nv16|yuyv422|uyvy422|p210*)  echo 422 ;;
    yuv444p*|yuvj444p|gbrp*|nv24|rgb*|bgr*|0rgb|rgb0|bgr0|argb|rgba|bgra|abgr) echo 444 ;;
    gray*|ya8|ya16*)                               echo gray ;;
    *)                                             echo "" ;;
  esac
}
mt_pix_depth() {
  case $1 in
    *p9le|*p9be|*9le) echo 9 ;;
    *p10*|*10le|*10be|p010*) echo 10 ;;
    *p12*|*12le|*12be|p012*) echo 12 ;;
    *p14*|*14le) echo 14 ;;
    *p16*|*16le|*16be) echo 16 ;;
    '') echo "" ;;
    *) echo 8 ;;
  esac
}

# ------------------------------------------------------------- ffprobe ---
# Stream records are read with ffprobe's "compact" writer, which prints
# key=value pairs, so parsing never depends on ffprobe's internal column order.
MT_SEP=$'\x1f'
declare -A S_TYPE=() S_CODEC=() S_PROFILE=() S_PIX=() S_W=() S_H=() S_RFR=() S_AFR=()
declare -A S_BITS=() S_FMT=() S_RATE=() S_CH=() S_LAYOUT=() S_FIELD=() S_RANGE=()
declare -A S_SPACE=() S_TRC=() S_PRIM=() S_LANG=() S_TITLE=() S_DEFAULT=() S_PIC=() S_SAR=()
MT_VID=(); MT_AUD=(); MT_SUB=(); MT_PIC=(); MT_DATA=(); MT_ATT=()
FMT_NAME=""; FMT_DUR=""

# mt_probe_streams FILE   (needs $FFPROBE) - returns 1 if the file can't be read
mt_probe_streams() {
  local file=$1 out line f key val idx
  local -a kv
  local -A r
  S_TYPE=(); S_CODEC=(); S_PROFILE=(); S_PIX=(); S_W=(); S_H=(); S_RFR=(); S_AFR=()
  S_BITS=(); S_FMT=(); S_RATE=(); S_CH=(); S_LAYOUT=(); S_FIELD=(); S_RANGE=()
  S_SPACE=(); S_TRC=(); S_PRIM=(); S_LANG=(); S_TITLE=(); S_DEFAULT=(); S_PIC=(); S_SAR=()
  MT_VID=(); MT_AUD=(); MT_SUB=(); MT_PIC=(); MT_DATA=(); MT_ATT=()

  out=$("$FFPROBE" -v error \
    -show_entries "stream=index,codec_type,codec_name,profile,pix_fmt,width,height,sample_aspect_ratio,r_frame_rate,avg_frame_rate,bits_per_raw_sample,sample_fmt,sample_rate,channels,channel_layout,field_order,color_range,color_space,color_transfer,color_primaries:stream_tags=language,title:stream_disposition=default,attached_pic" \
    -of "compact=p=0:s=$MT_SEP" -i "file:$file" 2>/dev/null) || return 1
  [[ -n $out ]] || return 1

  while IFS= read -r line; do
    [[ -n $line ]] || continue
    IFS=$MT_SEP read -r -a kv <<<"$line"
    r=()
    for f in "${kv[@]}"; do
      key=${f%%=*}; val=${f#*=}
      [[ $val == N/A || $val == unknown ]] && val=''
      r[$key]=$val
    done
    idx=${r[index]:-}
    [[ -n $idx ]] || continue
    S_TYPE[$idx]=${r[codec_type]:-}
    S_CODEC[$idx]=${r[codec_name]:-}
    S_PROFILE[$idx]=${r[profile]:-}
    S_PIX[$idx]=${r[pix_fmt]:-}
    S_W[$idx]=${r[width]:-}
    S_H[$idx]=${r[height]:-}
    S_SAR[$idx]=${r[sample_aspect_ratio]:-}
    S_RFR[$idx]=${r[r_frame_rate]:-}
    S_AFR[$idx]=${r[avg_frame_rate]:-}
    S_BITS[$idx]=${r[bits_per_raw_sample]:-}
    S_FMT[$idx]=${r[sample_fmt]:-}
    S_RATE[$idx]=${r[sample_rate]:-}
    S_CH[$idx]=${r[channels]:-}
    S_LAYOUT[$idx]=${r[channel_layout]:-}
    S_FIELD[$idx]=${r[field_order]:-}
    S_RANGE[$idx]=${r[color_range]:-}
    S_SPACE[$idx]=${r[color_space]:-}
    S_TRC[$idx]=${r[color_transfer]:-}
    S_PRIM[$idx]=${r[color_primaries]:-}
    S_LANG[$idx]=${r[tag:language]:-}
    S_TITLE[$idx]=${r[tag:title]:-}
    S_DEFAULT[$idx]=${r[disposition:default]:-0}
    S_PIC[$idx]=${r[disposition:attached_pic]:-0}
    case ${S_TYPE[$idx]} in
      video)      if [[ ${S_PIC[$idx]} == 1 ]]; then MT_PIC+=("$idx"); else MT_VID+=("$idx"); fi ;;
      audio)      MT_AUD+=("$idx") ;;
      subtitle)   MT_SUB+=("$idx") ;;
      attachment) MT_ATT+=("$idx") ;;
      *)          MT_DATA+=("$idx") ;;
    esac
  done <<<"$out"
  return 0
}

# mt_probe_format FILE - sets FMT_NAME, FMT_DUR (seconds, may be empty)
mt_probe_format() {
  local out
  FMT_NAME=""; FMT_DUR=""
  out=$("$FFPROBE" -v error -show_entries format=format_name,duration \
        -of default=noprint_wrappers=1 -i "file:$1" 2>/dev/null) || return 1
  FMT_NAME=$(sed -n 's/^format_name=//p' <<<"$out")
  FMT_DUR=$(sed -n 's/^duration=//p' <<<"$out")
  [[ $FMT_DUR == N/A ]] && FMT_DUR=""
  return 0
}

# mt_hms SECONDS -> H:MM:SS
mt_hms() { awk -v s="${1:-0}" 'BEGIN{s=int(s+0.5); printf "%d:%02d:%02d", s/3600, (s%3600)/60, s%60}'; }

# mt_color_ok KIND VALUE - true if ffprobe's colour-tag name is also a valid ffmpeg
# option value.  (ffprobe prints e.g. "gbr" for RGB, which -colorspace rejects.)
#   KIND: prim | trc | space
mt_color_ok() {
  case $1:$2 in
    prim:bt709|prim:bt470m|prim:bt470bg|prim:smpte170m|prim:smpte240m|prim:film|prim:bt2020|prim:smpte428|prim:smpte431|prim:smpte432) return 0 ;;
    trc:bt709|trc:gamma22|trc:gamma28|trc:smpte170m|trc:smpte240m|trc:linear|trc:log100|trc:log316|trc:iec61966-2-4|trc:bt1361e|trc:iec61966-2-1|trc:bt2020-10|trc:bt2020-12|trc:smpte2084|trc:smpte428|trc:arib-std-b67) return 0 ;;
    space:bt709|space:fcc|space:bt470bg|space:smpte170m|space:smpte240m|space:bt2020nc|space:bt2020c|space:ycgco|space:smpte2085) return 0 ;;
  esac
  return 1
}
