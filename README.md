# MediaScripts

**Image conversion, DaVinci Resolve preparation, and automatic black-bar cropping for Linux.**

Three independent Bash tools designed for KDE Plasma 6 on CachyOS/Arch Linux. Use them from the terminal, Dolphin's right-click menu, or the application launcher. No background services.

| Tool | Purpose | Typical output |
| --- | --- | --- |
| `img2png` | Convert images (including GIMP XCF) to PNG | `photo.png` |
| `resolve-prep` | Convert audio and/or video to editing-friendly formats | MOV or MKV with PCM audio and/or DNxHR video |
| `crop-bars` | Detect, preview and remove black bars | Cropped video with audio/subtitles copied |

## Installation

### Requirements

Arch/CachyOS:

```bash
sudo pacman -S --needed bash python ffmpeg imagemagick file kdialog konsole
```

Optional: `gimp` (GIMP 3 for XCF files), `libavif` and `libwebp` (dedicated AVIF/WebP decoders), `libva-mesa-driver` and `libva-utils` (AMD VA-API encoding). `crop-bars --encoder x264` or `x265` works without VA-API.

### One-command installer

Clone the repository and install as your **normal desktop user**, without `sudo`:

```bash
git clone https://github.com/isaacm0880/MediaScripts.git
cd MediaScripts
bash install.sh
```

The default destination is `~/.local/opt/media-tools`. To choose another directory:

```bash
bash install.sh --prefix ~/Custom/Scripts/media-tools
```

The installer copies the scripts and example configuration, updates the absolute paths in KDE desktop entries, and installs:

| Component | Destination |
| --- | --- |
| Scripts and shared library | `~/.local/opt/media-tools/` (or your prefix) |
| Dolphin context menu entries | `~/.local/share/kio/servicemenus/` |
| Application launcher entries | `~/.local/share/applications/` |
| Backups of previously installed managed files | `<prefix>/.install-backups/<timestamp>/` |

Restart Dolphin if the context menu doesn't refresh immediately. The installed scripts can be invoked with their full paths, or you can add `<prefix>/bin` to your shell's PATH.

For Fish, with the default prefix:

```fish
fish_add_path ~/.local/opt/media-tools/bin
```

### Updating

Pull the latest repository changes and rerun the installer with **the same prefix**:

```bash
git pull --ff-only
bash install.sh
```

For a custom installation, use `bash install.sh --prefix /your/existing/path` again. The installer backs up files it replaces. It doesn't remove unrelated scripts or old context-menu entries.

## Usage

### img2png — image to PNG

```bash
img2png "photo.webp"
img2png *.jpg *.xcf
img2png -o ~/Pictures/converted "image.avif"
img2png --skip-existing *.tif
img2png --pick
```

- Identifies images by content rather than trusting the filename extension.
- Uses GIMP 3 to export the visible composite of XCF projects.
- Prefers `avifdec` for AVIF and `dwebp` for WebP, falling back to ImageMagick when supported.
- Preserves transparency where supported; exports the first frame/page of animated or multipage formats.
- Doesn't overwrite existing output by default. Use `--overwrite` only when intentional.

### resolve-prep — DaVinci Resolve conversion

Choose what to convert. Codec analysis provides advice; it doesn't override your selected mode.

```bash
resolve-prep "video.mkv"                    # Interactive mode selection
resolve-prep --analyze "video.mkv"          # Inspect only
resolve-prep --audio-only "video.mkv"       # PCM audio, copy video
resolve-prep --video-only "video.mkv"       # DNxHR video, copy audio
resolve-prep --both "video.mkv"             # Convert both
resolve-prep --audio-only --dry-run "video.mkv"
resolve-prep --both --yes "video.mkv"       # Skip CLI confirmation
resolve-prep --prefer-lang eng,jpn --subs sidecar -o ~/Videos/out --audio-only "video.mkv"
```

| Mode | Video | Audio |
| --- | --- | --- |
| `--audio-only` | Stream copy | Convert non-PCM to PCM |
| `--video-only` | Convert to DNxHR | Stream copy |
| `--both` | Convert to DNxHR | Convert non-PCM to PCM |
| `--analyze` | No changes | No changes |

Running without a mode opens an interactive menu. The plan is displayed before conversion, and the confirmation **defaults to Yes**: `[Y/n/q]` (Enter to continue, `n` to cancel, `q` to quit). The `--yes` flag skips the CLI confirmation.

The default container is MOV; if a copied stream is incompatible with MOV, the tool can offer MKV rather than silently re-encoding the stream. Text subtitles can be exported as SRT sidecars. Input files are not overwritten; output names are made unique.

**Important:** Resolve compatibility depends on codec, pixel format, hardware and Resolve version. The tool's assessment is guidance, not a guarantee. DNxHR output can be much larger than the source. See `--help` for all options.

### crop-bars — detect and remove black bars

```bash
crop-bars --analyze "film.mkv"                   # Detect only
crop-bars "film.mkv"                             # Preview, then confirm
crop-bars --yes "film.mkv"                       # Encode validated crop
crop-bars --crop 1920:800:0:140 "film.mkv"        # Manual W:H:X:Y
crop-bars --bars 0,140,0,140 "film.mkv"           # Manual L,T,R,B
crop-bars --encoder x265 --quality 20 "film.mkv" # CPU encoding
```

The detector samples multiple timestamps, compares bar measurements and independently validates the proposed crop. It uses a conservative safety margin and reports **VALIDATED**, **AMBIGUOUS**, or **NONE**. Preview images are saved under `~/.cache/media-tools/previews/`; review them before encoding.

Default encoding uses AMD HEVC VA-API at QP 18. CPU `x264` and `x265` are alternatives. Audio and subtitle streams are copied where supported. Hardware encoding may not preserve all HDR metadata.

## Configuration

The optional configuration examples live in `conf examples/`. Copy only those you need to `~/.config/media-tools/`, removing the `.example` suffix:

```bash
mkdir -p ~/.config/media-tools
cp "conf examples/resolve-prep.conf.example" ~/.config/media-tools/resolve-prep.conf
```

There are corresponding examples for `img2png` and `crop-bars`. Review their comments before editing.

## Testing

Run the bundled synthetic-media smoke tests:

```bash
bash lib/run-tests.sh
```

The suite checks representative conversion, output naming, validation and failure paths. It is **not** a substitute for testing GIMP XCF export, GPU VA-API encoding, Dolphin integration, or your installed DaVinci Resolve version with real files.

## Repository layout

```text
MediaScripts/
├── install.sh
├── bin/
│   ├── img2png
│   ├── resolve-prep
│   └── crop-bars
├── lib/
│   ├── common.sh
│   └── run-tests.sh
├── conf examples/
│   ├── img2png.conf.example
│   ├── resolve-prep.conf.example
│   └── crop-bars.conf.example
├── desktops/             # Dolphin service menus
└── launchers/             # Application menu launchers
```

## Notes and limitations

- These tools operate on local files; no daemons or watchers are installed.
- The original input is retained. Conversion outputs are written separately.
- Very dark scenes, subtitles in letterbox regions and unusual aspect ratios can make automatic cropping uncertain. Inspect previews.
- Temporary output and interruption handling should be verified before relying on the tools for important media; retain backups of irreplaceable files.
- Desktop launchers require KDE utilities, particularly Konsole and (for file selection) KDialog.
