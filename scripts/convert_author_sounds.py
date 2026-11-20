#!/usr/bin/env python3
"""Convert the author's recordings into AlarmKit sounds.

Reads assets/author-sounds/author_1.m4a … author_6.m4a and writes
WakeMeUp/Sounds/author1.caf … author6.caf. The m4a files stay in that
folder so this can be run again. They are not part of the app target.

Output matches the synthesized tones: 44.1 kHz mono Apple IMA4 CAF.
Anything longer than 30 seconds is cut to just under 30 seconds, which is
what AlarmKit and notification sounds accept, with a 2 second fade-out.
author_4 is shorter, so it is only loudness-matched. Loudness uses the same
ceiling as scripts/generate_sounds.py (peak 0.84, or -9 dB mean square,
whichever is lower) so nothing clips.

`python3 scripts/convert_author_sounds.py --check` only reads the CAF files.
"""

from __future__ import annotations

import math
import struct
import subprocess
import sys
import wave
from pathlib import Path

np = None  # Imported only when converting. --check stays on the standard library.

SR = 44100
FADE_SECONDS = 2.0
# Just under 30 seconds, and a whole number of 64-sample IMA packets.
MAX_FRAMES = (int(30 * SR) // 64) * 64
PEAK = 0.84
TARGET_MEAN_SQUARE = 0.12589254
ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "assets" / "author-sounds"
OUTPUT_DIR = ROOT / "WakeMeUp" / "Sounds"
# Stable ids author1…author6. The source files keep the upload names.
PAIRS = tuple((f"author_{index}.m4a", f"author{index}.caf") for index in range(1, 7))


def decode(path: Path) -> np.ndarray:
    raw = subprocess.check_output(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-i", str(path),
            "-map_metadata", "-1",
            "-ac", "1",
            "-ar", str(SR),
            "-f", "f32le",
            "-",
        ]
    )
    samples = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    if samples.size == 0:
        raise RuntimeError(f"{path.name} decoded to silence")
    return samples


def shape(samples: np.ndarray) -> np.ndarray:
    """Trim long recordings. Leave a short one at its own length."""
    if len(samples) > MAX_FRAMES:
        clipped = samples[:MAX_FRAMES].copy()
        fade = int(FADE_SECONDS * SR)
        ramp = 0.5 * (1 + np.cos(np.linspace(0, math.pi, fade)))
        clipped[-fade:] *= ramp
        return clipped
    extra = (-len(samples)) % 64
    if extra:
        return np.pad(samples, (0, extra))
    return samples


def normalize(samples: np.ndarray) -> np.ndarray:
    peak = float(np.max(np.abs(samples)))
    mean_square = float(np.mean(samples * samples))
    if peak == 0 or mean_square == 0:
        raise RuntimeError("recording is silent")
    gain = min(PEAK / peak, math.sqrt(TARGET_MEAN_SQUARE / mean_square))
    return np.clip(samples * gain, -PEAK, PEAK)


def write_caf(name: str, samples: np.ndarray) -> Path:
    destination = OUTPUT_DIR / name
    temporary = OUTPUT_DIR / f".{name}.wav"
    pcm = np.clip(np.round(samples * 32767), -32767, 32767).astype(np.int16)
    with wave.open(str(temporary), "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(pcm.tobytes())
    subprocess.run(
        [
            "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
            "-i", str(temporary),
            "-map_metadata", "-1",
            "-c:a", "adpcm_ima_qt",
            "-ar", str(SR),
            "-ac", "1",
            str(destination),
        ],
        check=True,
    )
    temporary.unlink()
    return destination


def read_caf(path: Path) -> tuple[float, int]:
    data = path.read_bytes()
    if data[:4] != b"caff":
        raise RuntimeError(f"{path.name} is not a CAF file")
    offset = 8
    frames = 0
    sample_rate = 0.0
    while offset + 12 <= len(data):
        kind = data[offset:offset + 4]
        size = struct.unpack_from(">q", data, offset + 4)[0]
        body = offset + 12
        if kind == b"desc":
            sample_rate, fmt, _flags, bpf, fpp, channels, _bits = struct.unpack_from(
                ">dIIiiII", data, body
            )
            if fmt.to_bytes(4, "big") != b"ima4" or channels != 1 or bpf != 34 or fpp != 64:
                raise RuntimeError(f"{path.name} is not mono IMA4")
            if abs(sample_rate - SR) > 0.1:
                raise RuntimeError(f"{path.name} sample rate is {sample_rate}")
        elif kind == b"data":
            payload = size - 4
            if payload % 34 != 0:
                raise RuntimeError(f"{path.name} IMA data is not a whole number of packets")
            frames = (payload // 34) * 64
        if size < 0:
            break
        offset = body + size
    if frames == 0:
        raise RuntimeError(f"{path.name} has no audio")
    return sample_rate, frames


def decoded_peak(path: Path) -> float:
    raw = subprocess.check_output(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-i", str(path),
            "-f", "f32le", "-ac", "1", "-ar", str(SR),
            "-",
        ]
    )
    audio = np.frombuffer(raw, dtype=np.float32)
    return float(np.max(np.abs(audio))) if audio.size else 0.0


def convert() -> None:
    if subprocess.call(["ffmpeg", "-version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) != 0:
        raise SystemExit("ffmpeg is required to convert the author recordings")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for source_name, output_name in PAIRS:
        source = SOURCE_DIR / source_name
        if not source.is_file():
            raise SystemExit(f"missing {source}")
        audio = normalize(shape(decode(source)))
        destination = write_caf(output_name, audio)
        _rate, frames = read_caf(destination)
        duration = frames / SR
        peak = decoded_peak(destination)
        print(f"wrote {output_name}: {duration:.3f}s, peak {peak:.3f}, {destination.stat().st_size} bytes")
        if duration >= 30:
            raise SystemExit(f"{output_name} is {duration:.3f}s, which is not under 30 seconds")
        if peak > 0.98:
            raise SystemExit(f"{output_name} peaks at {peak}")
        if output_name == "author4.caf" and duration > 12:
            raise SystemExit("author4 should stay at its original short length")
        if output_name != "author4.caf" and duration < 29:
            raise SystemExit(f"{output_name} should be trimmed to just under 30 seconds")


def check() -> None:
    for _source_name, output_name in PAIRS:
        path = OUTPUT_DIR / output_name
        if not path.is_file():
            raise SystemExit(f"missing {path}")
        _rate, frames = read_caf(path)
        duration = frames / SR
        if duration >= 30:
            raise SystemExit(f"{output_name} is {duration:.3f}s")
        if output_name == "author4.caf" and not 8 <= duration <= 12:
            raise SystemExit(f"author4.caf is {duration:.3f}s; it should stay near 9.6 seconds")
        if output_name != "author4.caf" and not 29 <= duration < 30:
            raise SystemExit(f"{output_name} is {duration:.3f}s; expected a 30 second trim")
        print(f"{output_name} {duration:.3f}s {path.stat().st_size} bytes")
    print(f"{len(PAIRS)} author sounds")


def main() -> None:
    if "--check" in sys.argv:
        check()
        return
    global np
    import numpy as np
    convert()


if __name__ == "__main__":
    main()
