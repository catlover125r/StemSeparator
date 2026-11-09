# StemSeparator

A small Mac app that splits a song into vocals and instrumentals (and individual stems) by dragging audio files onto a window. It runs [Demucs](https://github.com/facebookresearch/demucs) under the hood and queues multiple files.

- Drop audio files onto the window; they process one after another.
- Save the vocals, or save the instrumentals, with one click.
- Apple Silicon Macs only (arm64).

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

The first separation downloads the Demucs model weights (a few hundred MB), so it needs an internet connection and takes longer once.

The app looks for `demucs` in `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, and the python.org Python 3.11, 3.12 and 3.13 `bin` folders. If it says "demucs not found", install it with one of those Python setups.

## Notes

This repo currently hosts the built app only; the Swift source isn't included.
