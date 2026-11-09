# StemSeparator

A small Mac app that splits a song into vocals and instrumentals (or individual stems) by dragging audio files onto a window. It runs [Demucs](https://github.com/facebookresearch/demucs) under the hood and queues multiple files.

- Drop audio files onto the window, or click it to choose files. They process one after another.
- Save the vocals, the instrumental, or every stem with one click.
- First launch walks you through downloading the models you want.
- Apple Silicon Macs only (arm64), macOS 14 or later.

## Install

1. Install Demucs, which does the actual separation:
   ```sh
   pip3 install demucs
   ```
   You also need `ffmpeg` for MP3 input: `brew install ffmpeg`.
2. Download `StemSeparator.zip` from the [latest release](../../releases/latest), unzip it, and drag **StemSeparator.app** into `/Applications`.
3. The app isn't notarized, so macOS will refuse to open it the first time. Either right-click the app and choose **Open**, or run:
   ```sh
   xattr -dr com.apple.quarantine /Applications/StemSeparator.app
   ```
4. On first launch the app checks for Demucs and offers to download models. Open **Models** in the toolbar any time to download more.

## Models

| Model | Download | Notes |
|---|---|---|
| Standard (`htdemucs`) | 84 MB | Vocals, drums, bass, other. Fast; the default |
| High quality (`htdemucs_ft`) | 337 MB | Same stems, cleaner, about 4x slower |
| Six stems (`htdemucs_6s`) | 55 MB | Adds guitar and piano |

Models come from Meta's public Demucs release (`dl.fbaipublicfiles.com`), are checked against their published SHA-256 prefix, and are saved to `~/.cache/torch/hub/checkpoints`, where Demucs itself looks for them. If you already use Demucs, any models you have are detected automatically.

## Build from source

```sh
./build.sh             # builds build/StemSeparator.app
./build.sh --install   # also copies it to /Applications
```

Needs the Xcode command line tools (`swiftc`); no Xcode project.
