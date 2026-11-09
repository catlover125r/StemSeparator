#!/usr/bin/env python3
"""stemsep: split a song into stems (vocals, drums, bass, other) using Demucs."""

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

AUDIO_EXTS = {".mp3", ".wav", ".flac", ".m4a", ".aac", ".ogg", ".aiff"}
MODELS = ["htdemucs", "htdemucs_ft", "htdemucs_6s", "mdx_extra"]


def collect_inputs(paths):
    files = []
    for p in map(Path, paths):
        if p.is_dir():
            files += sorted(f for f in p.iterdir() if f.suffix.lower() in AUDIO_EXTS)
        elif p.is_file():
            files.append(p)
        else:
            sys.exit(f"stemsep: not found: {p}")
    if not files:
        sys.exit("stemsep: no audio files found")
    return files


def main():
    ap = argparse.ArgumentParser(prog="stemsep", description=__doc__)
    ap.add_argument("inputs", nargs="+", help="audio files or folders of audio files")
    ap.add_argument("-o", "--out", default="stems", help="output folder (default: ./stems)")
    ap.add_argument("-m", "--model", default="htdemucs", choices=MODELS,
                    help="htdemucs_6s adds guitar and piano; htdemucs_ft is slower but cleaner")
    ap.add_argument("--two-stems", metavar="STEM",
                    help="only split one stem from the rest, e.g. vocals (gives vocals + no_vocals)")
    ap.add_argument("--mp3", action="store_true", help="export MP3 instead of WAV")
    ap.add_argument("--device", choices=["cpu", "cuda", "mps"],
                    help="force a device (default: auto)")
    args = ap.parse_args()

    if shutil.which("demucs") is None:
        sys.exit("stemsep: demucs not found. Install with: pip install -r requirements.txt")

    for f in collect_inputs(args.inputs):
        cmd = ["demucs", "-n", args.model, "-o", args.out]
        if args.two_stems:
            cmd += ["--two-stems", args.two_stems]
        if args.mp3:
            cmd += ["--mp3"]
        if args.device:
            cmd += ["-d", args.device]
        cmd.append(str(f))
        print(f"==> {f.name}")
        if subprocess.run(cmd).returncode != 0:
            sys.exit(f"stemsep: demucs failed on {f}")
        print(f"    stems in {Path(args.out) / args.model / f.stem}")


if __name__ == "__main__":
    main()
