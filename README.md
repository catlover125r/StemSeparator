# StemSeparator

Split a song into stems (vocals, drums, bass, other) from the command line. A thin wrapper around [Demucs](https://github.com/facebookresearch/demucs) that takes files or whole folders and handles the flags for you.

## Setup

```sh
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

## Usage

```sh
./stemsep.py song.mp3                      # vocals, drums, bass, other
./stemsep.py ~/Music/album/                # every audio file in a folder
./stemsep.py song.mp3 --two-stems vocals   # vocals + instrumental only
./stemsep.py song.mp3 -m htdemucs_6s       # also guitar and piano
./stemsep.py song.mp3 --mp3 -o ~/Desktop/stems
```

Output lands in `stems/<model>/<song name>/`. On Apple Silicon, `--device mps` can speed things up.

| Model | Notes |
|---|---|
| `htdemucs` | Default, good balance of speed and quality |
| `htdemucs_ft` | Fine-tuned, cleaner but about 4x slower |
| `htdemucs_6s` | Six stems, adds guitar and piano (piano is weaker) |
| `mdx_extra` | Alternative architecture |

Model weights download automatically on first run.
