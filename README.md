# media-tools — img2png, resolve-prep, crop-bars

## Quick install (recommended)

Clone the repository, then run the installer as your normal desktop user (not sudo):

```fish
git clone https://github.com/isaacm0880/MediaScripts.git
cd MediaScripts
bash install.sh
```

Default installation: `~/.local/opt/media-tools`. Choose another location with:

```fish
bash install.sh --prefix ~/Custom/Scripts/media-tools
```

The installer copies the scripts, shared library and example configs; rewrites the absolute paths in all KDE service-menu and application-launcher entries; installs those entries into the correct per-user XDG directories; and refreshes KDE's cache. Existing managed files are backed up to `<prefix>/.install-backups/<timestamp>/` when present. The source checkout can be kept for updates. Restart Dolphin to refresh its context menu.

**Note:** The older manual installation and update instructions below use historical folder names (`desktop/`, `config/`, `tests/`). The actual repository folders are `desktops/`, `conf examples/`, and `lib/`. Use `install.sh` instead.


Three manually-run Bash tools for CachyOS / KDE Plasma 6 (Wayland) / Fish. No daemons, no watchers.

```
media-tools/
  bin/img2png  bin/resolve-prep  bin/crop-bars
  lib/common.sh                    shared helpers (probe, naming, temp files, config)
  desktop/*.desktop                3 Dolphin right-click entries + 3 launcher entries
  config/*.conf.example            optional per-tool settings
  tests/run-tests.sh               synthetic-media smoke tests
```

**Install root assumed:** `/home/isaac/Custom/Scripts/media-tools` — derived from the report's
`/home/isaac/Custom/Scripts/`. The report does not say this is where you want new tools; confirm or
retarget with the `sed` command below. A new sub-folder is used so nothing existing is touched.

## Dependencies (Arch package names)

| Package | Needed by | Notes |
|---|---|---|
| `ffmpeg` | resolve-prep, crop-bars | provides `ffprobe` too |
| `imagemagick` | img2png | provides `magick` (v7) |
| `file` | img2png | content-based format detection |
| `gimp` (3.x) | img2png, XCF only | uses GIMP 3 Python API; the script refuses GIMP 2.x |
| `libavif`, `libwebp` | img2png, optional | `avifdec` / `dwebp` are preferred when present, ImageMagick is the fallback |
| `kdialog` | launcher entries (`--pick`) | |
| `konsole` | all `.desktop` files | already installed |
| `libva-mesa-driver`, `libva-utils` | crop-bars `vaapi-*` encoders | AMD VA-API; not needed for `x264`/`x265` |

Everything except `gimp`, `libavif`, `libwebp`, `libva-*` is probably already present; I could not check
(the report did not establish it).

## Install (Fish)

```fish
set -l SRC ~/Downloads/media-tools          # where you unpacked this
set -l DEST /home/isaac/Custom/Scripts/media-tools

test -e $DEST; and echo "$DEST already exists - stop and review"
mkdir -p $DEST; and cp -rn $SRC/. $DEST/    # -n: never overwrite
chmod +x $DEST/bin/* $DEST/desktop/*.desktop $DEST/tests/run-tests.sh

# (only if your install root differs from the one written into the .desktop files)
# sed -i "s|/home/isaac/Custom/Scripts/media-tools|$DEST|g" $DEST/desktop/*.desktop

# Dolphin right-click entries (Plasma 6 requires the .desktop files to be executable)
mkdir -p ~/.local/share/kio/servicemenus
for f in $DEST/desktop/media-tools-{img2png,resolve-prep,crop-bars}.desktop
    test -e ~/.local/share/kio/servicemenus/(basename $f); and echo "exists, skipped: $f"; or cp $f ~/.local/share/kio/servicemenus/
end

# Application-launcher entries (file picker variants)
mkdir -p ~/.local/share/applications
for f in $DEST/desktop/media-tools-*-launcher.desktop
    test -e ~/.local/share/applications/(basename $f); and echo "exists, skipped: $f"; or cp $f ~/.local/share/applications/
end
kbuildsycoca6          # refresh KDE's menu cache; restart Dolphin
```

Optional: `mkdir -p ~/.config/media-tools; cp $DEST/config/resolve-prep.conf.example ~/.config/media-tools/resolve-prep.conf`.
Optional shell access: `fish_add_path $DEST/bin`.

**Launch model.** Dolphin right-click is the practical way to hand files to the tools; each entry opens
Konsole, shows the report and keeps the window open until Enter (`--pause`). The `*-launcher.desktop`
entries appear in the application menu and open a KDE file dialog (`--pick`). If kdialog is missing
they print an install hint instead of silently doing nothing.

## Existing report items: reuse / replace / supersede

The report's inventory is the baseline. My reading of it, and what happens (nothing is deleted):

* Old XCF→PNG logic (GIMP `--no-interface` + Python-Fu `file_load`/`file_save`): **reused** in `img2png`
  (same call, now fed through environment variables, with timeout and output verification).
* Old PNG converter script and its service-menu entry: **superseded** by `img2png`.
* Old Resolve audio converter (always PCM into MKV/MP4, flac allowed, per-codec lists): **superseded** by `resolve-prep`, which now lets you choose the mode.
* Old crop script (single `cropdetect`, round=16, `hevc_vaapi` QP 18): **superseded** by `crop-bars`; the
  VAAPI HEVC QP 18 default and colour-tag propagation are kept.
* New entries are named with distinct file names and "(v2)" labels, so both old and new can coexist.

## Migration plan (non-destructive)

1. Install as above; old scripts and entries keep working.
2. Run the tests (below), then try each tool on copies of real files.
3. In Dolphin you will see old and new menu items side by side. To hide an old one, *you* move its
   `.desktop` out of `~/.local/share/kio/servicemenus/` into a backup folder (`mkdir -p ~/old-menus; mv ...`).
   I have not provided any command that deletes anything; deleting old scripts is your call after you are satisfied.

## img2png

```fish
img2png "photo (1).webp"                 # -> "photo (1).png" beside it
img2png *.xcf *.jpg                      # several files
img2png -o ~/Pictures/png-out "a b.avif" # elsewhere
img2png --skip-existing *.tif            # never touch files whose .png exists
```

* **Detection** is by content (`file --mime-type`; XCF also by its `gimp xcf ` header), so a JPEG named `.png` is converted correctly (and not clobbered: the output becomes `name (2).png`).
* **Tool choice:** XCF→GIMP 3 batch; AVIF→`avifdec`; WebP→`dwebp`; JPEG, TIFF, BMP, GIF, HEIC, JP2, JXL, PSD, TGA, ICO, PNM→ImageMagick. Failure of the first tool falls through to the next where one exists.
* **Transparency** is preserved by every path (PNG keeps alpha; none of the commands flattens onto a background).
* **Layered XCF:** GIMP's PNG export writes the **visible composite** of the image: visible layers, with their opacity, modes, masks and groups, merged. **Hidden layers are not included** and layers are not exported separately. I describe this from GIMP's export behaviour; I could not run GIMP here to confirm it on your files. Text layers need installed fonts to render the same.
* Animated GIF/WebP, multi-page TIFF, ICO: first frame/page only (printed as a note). EXIF orientation is applied.
* Exit codes: 0 ok, 1 any failure, 2 usage/missing dependency.

## resolve-prep

**You choose what is converted; codec detection only advises.** Pick the mode from the menu, or on the command line:

```fish
resolve-prep "My Film (2020).mkv"               # no mode -> interactive menu
resolve-prep --audio-only "video.mkv"           # audio -> PCM, video stream-copied
resolve-prep --video-only "video.mkv"           # video -> DNxHR, audio stream-copied
resolve-prep --both "video.mkv"                 # convert both
resolve-prep --analyze "video.mkv"              # inspect + recommend; writes nothing
resolve-prep --audio-only -n *.mkv              # dry run: plan + exact ffmpeg command
resolve-prep --audio-only --yes film.mkv        # skip the final "Proceed?" (CLI mode only)
resolve-prep --prefer-lang eng,jpn --subs sidecar -o ~/out --audio-only film.mkv
```

### Menu (shown when no mode is given)
```
1) Audio only   2) Video only   3) Both audio and video
4) Analyse the file and recommend a conversion (no encoding)   5) Exit
```
* Nothing starts until you choose; option 4 is analysis-only and returns to the menu so you can then act on the advice.
* With several files (e.g. several selected in Dolphin) each file gets a header `File 2 of 5: name`, its own menu and its own confirmation. After choosing 1-3 you are asked whether to apply that mode to all remaining files; the final `Proceed? [y/N/q]` is still asked per file (`q` stops the whole run).
* Without a terminal and without a mode flag the script refuses (exit 2) instead of guessing.

### What each mode does
| Mode | Video | Audio | Notes |
|---|---|---|---|
| `--audio-only` | always stream-copied | non-PCM tracks -> PCM, PCM tracks copied | warns if the video is flagged risky, but copies it anyway |
| `--video-only` | converted to DNxHR | always copied unchanged | warns if the audio is flagged (e.g. AAC stays undecodable in Resolve) |
| `--both` | converted | non-PCM -> PCM | |
| `--analyze` | not touched | not touched | assessment + recommendation only; no remux, no sidecar files |

* A stream not selected is never re-encoded, whatever the assessment says. The assessment (`looks compatible` / `likely needs conversion` / `uncertain`, with reasons) is printed first, and any disagreement with your choice becomes a warning (e.g. "video #0 is flagged ... it is being COPIED UNCHANGED as you chose audio-only").
* **Container conflicts:** MOV is the default (PCM is native there). If a stream you chose to keep cannot be stored in MOV (e.g. Opus audio with `--video-only`, VP9 video with `--audio-only`) the script stops, lists the conflict and, in a terminal, asks: `1) use MKV instead  2) cancel`. Without a terminal it stops and tells you to pass `--container mkv`. It never silently converts the stream. With `--container mov` forced it refuses rather than convert.
* If `--audio-only` finds nothing to convert (all PCM) it warns that the result is just a remux; if there is no audio stream it stops.
* `--cfr` needs `--video-only`/`--both` (it changes the video); with `--audio-only` it is rejected.
* **Plan summary before encoding:** input, mode, each audio/video stream (CONVERT or COPY), container, subtitle handling, output name, streams not carried, warnings. Then `Proceed with this plan? [y/N/q]`. FFmpeg progress is shown while it runs; success/failure is reported at the end.
* Kept from before: `--pcm-bits`, `--video-target`, `--prefer-lang` (reorders, never drops), `--subs sidecar|keep|drop`, `--container`, `-o/--out-dir`, `--suffix`, `--pick`, `--pause`, `-n/--dry-run`, never overwrite (timestamped/numbered names), temp file then atomic move, duration sanity check.
* **Removed/changed options:** `--audio auto|copy|convert`, `--video ...` and `--remux` are gone (the mode replaces them); `--analyze` is now a mode (use `-n` for a dry run of a real mode). Config keys `AUDIO_MODE`, `VIDEO_MODE`, `UNKNOWN_VIDEO_ACTION` are ignored; `MOV_AUDIO_OK` is new.

### Assessment policy (advice only)
* **Audio:** PCM is "compatible"; everything else is flagged. AAC is flagged because Resolve on Linux has no AAC decoder in any profile or container. AC-3/E-AC-3/DTS/TrueHD/MP3 on reports of missing or inconsistent support; FLAC/ALAC because Linux support is unconfirmed (conversion is lossless). PCM depth: 24-bit for lossless/high-bit sources, else 16-bit.
* **Video:** H.264/HEVC by pixel format: 4:2:0 8-bit H.264 and 4:2:0 8/10-bit HEVC look fine; 4:2:2, 4:4:4 and H.264 10-bit are flagged (AMD VCN cannot decode them). ProRes/DNxHD fine; AV1, VP8/VP9, FFV1 and unknown codecs flagged; MJPEG, MPEG-4, MPEG-2, CineForm "uncertain". DNxHR target: HQ (8-bit), HQX (>=10-bit), 444 for 4:4:4. Frame rate, resolution and colour tags are never altered.
* `.webm`/FLV/OGV/WMV are reported as container problems. Subtitles: `sidecar` (default) writes text subtitles to `.srt` beside the output; bitmap subtitles are reported and omitted.
* This policy comes from vendor forum reports and AMD hardware limits, **not from a test on your Resolve build**. Edit the lists in `~/.config/media-tools/resolve-prep.conf`.

### Limits
Metadata cannot prove an import will work. VFR is flagged heuristically. Data streams (GoPro telemetry) and cover art are not carried over (reported). DNxHR files are large (roughly 5-10x the H.264 original at HQ).

## crop-bars

```fish
crop-bars --analyze "wide film.mkv"        # report only
crop-bars "wide film.mkv"                  # analyse + previews + asks before encoding
crop-bars --yes "wide film.mkv"            # encode if validated
crop-bars --crop 1920:800:0:140 "wide film.mkv"   # manual rectangle W:H:X:Y
crop-bars --bars 0,140,0,140 clip.mp4      # manual bars L,T,R,B
crop-bars --encoder x265 --quality 20 film.mkv    # CPU encode
```

### How it decides
1. 16 sample points at the centre of equal slices across the video; at each, `cropdetect` runs over 8 consecutive frames with a cumulative bounding box.
2. Samples with no picture, mean luma < 30, or a detected area < 5% of the frame are discarded (dark scenes can only make bars look *larger*).
3. Per edge, the **smallest** bar among usable samples is taken, and ≥ 70% of usable samples must agree within ±4 px. Otherwise **AMBIGUOUS**: flagged, nothing encoded without confirmation. A crop removing > 60% of the frame is also flagged.
4. Safety margin (2 px), thin-bar floor (< 8 px = no bar) and rounding down (multiple of 2) always crop *less*.
5. **Independent validation** at 6 different timestamps: each strip to be removed is measured with `signalstats`; any luma above 48 (8-bit scale) rejects the crop (picture, subtitles or logos in the bars).
6. Report: source size, crop rectangle, result size, samples used/discarded, per-edge agreement, validation result, confidence, reasons.

Preview PNGs (red box = kept area) go to `~/.cache/media-tools/previews`, not beside the video.
Encoding: video re-encoded (VAAPI HEVC QP 18 by default, 10-bit kept when the source is 10-bit; 4:2:2/4:4:4 requires `x265`/`x264`),
all audio/subtitle streams copied, chapters/metadata kept, timestamps passed through (VFR preserved).
Exit status 3 means "left unchanged" (ambiguous or not confirmed).

Limits: a dim scene whose edge content is darker than luma ~24 looks like a bar; hard-coded subtitles
inside the bars lower agreement and flag the file; sources that are black at an edge by design (some animation, dark art) can still pass if every
sample agrees — always glance at the preview. HDR10 static metadata may not survive hardware encoding (a warning is printed).

## Test plan

`bash tests/run-tests.sh` builds synthetic clips in a temp folder and checks: AAC→audio-only plan and PCM output with video copied;
no-op on compatible files; WebM/VP9 → both; second run does not overwrite; originals bit-identical; filenames with spaces,
parentheses and quotes; bad/missing/non-media inputs exit 1; missing ffmpeg exits 2; letterbox detection with exact crop; no-bars → NONE;
unconfirmed run exits 3 and writes nothing; encoded result has the cropped size; bad manual crop rejected; JPG→PNG, no overwrite, non-image rejected.

Manual checks on real files (expected result in brackets):

```fish
resolve-prep --analyze your-aac-file.mkv   # [Recommended: AUDIO ONLY]
resolve-prep --audio-only -n your-aac-file.mkv   # [video COPY, audio CONVERT -> PCM]
resolve-prep --analyze your-4-2-2-file.mov # [video flagged with reason; nothing written]
crop-bars --analyze your-scope-film.mkv  # [VALIDATED + red-box previews]
crop-bars --analyze a-file-with-mixed-bars.mp4   # [AMBIGUOUS, nothing encoded]
img2png layered.xcf                      # [visible composite; compare with GIMP's File > Export]
chmod -w ~/some-readonly-dir; resolve-prep --audio-only --out-dir ~/some-readonly-dir x.mp4   # [clean "not writable" error]
```
Interrupt test: start a conversion, press Ctrl+C — temp `.mt-*.partial` files are removed and the original is untouched
(a `kill -9` could leave one hidden `.mt-*` file; it is safe to delete).

## Honest status

Tested in my own sandbox only (FFmpeg 6.1, ImageMagick 6 via a shim, synthetic media): `resolve-prep` and
`crop-bars` end to end, `img2png` with ImageMagick paths. **Not tested:** GIMP/XCF (no GIMP here), `avifdec`/`dwebp`, VAAPI encoding on
your RX 6800, the `.desktop` files in Plasma, Resolve itself. Nothing was run on your machine.

## Applying the resolve-prep update (Fish) - changed files only

Changed: `bin/resolve-prep`, `lib/common.sh` (one function added: `mt_color_ok`), `bin/crop-bars` (a small, essential fix: RGB sources carry a colour-matrix tag `gbr` that ffmpeg rejects; the same bug broke resolve-prep, so both now validate colour tags), `desktop/media-tools-resolve-prep*.desktop`, `tests/run-tests.sh`, `README.md`. `img2png` is untouched.

```fish
set -l SRC ~/Downloads/media-tools
set -l DEST /home/isaac/Custom/Scripts/media-tools
set -l BK ~/media-tools-backup-(date +%Y%m%d-%H%M%S)
mkdir -p $BK/bin $BK/lib $BK/desktop $BK/tests
# 1. back up what is about to be replaced
for f in bin/resolve-prep bin/crop-bars lib/common.sh desktop/media-tools-resolve-prep.desktop desktop/media-tools-resolve-prep-launcher.desktop tests/run-tests.sh README.md
    test -e $DEST/$f; and cp -p $DEST/$f $BK/$f
end
# 2. copy the new versions
for f in bin/resolve-prep bin/crop-bars lib/common.sh desktop/media-tools-resolve-prep.desktop desktop/media-tools-resolve-prep-launcher.desktop tests/run-tests.sh README.md
    cp $SRC/$f $DEST/$f
end
chmod +x $DEST/bin/* $DEST/desktop/*.desktop $DEST/tests/run-tests.sh
# 3. refresh the installed menu entries (they are copies)
cp $DEST/desktop/media-tools-resolve-prep.desktop ~/.local/share/kio/servicemenus/
cp $DEST/desktop/media-tools-resolve-prep-launcher.desktop ~/.local/share/applications/
kbuildsycoca6
```
The backup folder keeps your previous versions; nothing else is touched or deleted. Your old pre-v2 scripts are not involved.
