#!/usr/bin/env python3
"""Generate the bundled Wakito alarm tones.

The tones are synthesized in this script (sine, square, and exponential decay).
No third-party recordings are included. Output is 16-bit PCM WAV, mono, 22.05 kHz,
about 12 seconds each, which is under Apple's 30-second custom-alert limit.

After synthesis, ffmpeg loudnorm targets -9 LUFS with a -1 dBFS true-peak
ceiling so a ring is loud without clipping. Decaying tones stop at the peak
ceiling when they cannot also reach -9 LUFS.

License: CC0 1.0 Universal. See WakeMeUp/Sounds/LICENSE.txt.
"""

from __future__ import annotations

import json
import math
import shutil
import struct
import subprocess
import wave
from pathlib import Path

SAMPLE_RATE = 22050
SECONDS = 12
ROOT = Path(__file__).resolve().parents[1] / "WakeMeUp" / "Sounds"


def envelope(t: float, attack: float = 0.01, release: float = 0.08) -> float:
    if t < attack:
        return t / attack
    return 1.0


def write_wav(name: str, samples: list[float]) -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    path = ROOT / name
    with wave.open(str(path), "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        frames = bytearray()
        for sample in samples:
            clamped = max(-1.0, min(1.0, sample))
            frames += struct.pack("<h", int(clamped * 32767))
        handle.writeframes(frames)
    normalize(path)
    print(f"wrote {path} ({path.stat().st_size} bytes)")


def tone(freq: float, t: float) -> float:
    return math.sin(2 * math.pi * freq * t)


def classic() -> list[float]:
    samples: list[float] = []
    for i in range(SAMPLE_RATE * SECONDS):
        t = i / SAMPLE_RATE
        cycle = t % 1.0
        freq = 880 if cycle < 0.45 else 988
        gate = 1.0 if (cycle < 0.42 or 0.5 <= cycle < 0.92) else 0.0
        samples.append(0.55 * tone(freq, t) * gate)
    return samples


def chime() -> list[float]:
    samples: list[float] = []
    partials = (523.25, 659.25, 783.99, 1046.5)
    for i in range(SAMPLE_RATE * SECONDS):
        t = i / SAMPLE_RATE
        local = t % 1.6
        decay = math.exp(-0.5 * local)
        mixed = sum(tone(freq, t) * amp for freq, amp in zip(partials, (0.5, 0.25, 0.15, 0.1)))
        samples.append(mixed * decay)
    return samples


def rise() -> list[float]:
    samples: list[float] = []
    for i in range(SAMPLE_RATE * SECONDS):
        t = i / SAMPLE_RATE
        local = t % 3.0
        freq = 440 + (880 - 440) * (local / 3.0)
        # Integrate frequency so the sweep doesn't click.
        phase = 2 * math.pi * (440 * local + (440 * local * local) / 6.0)
        window = envelope(local, 0.02) * (1 if local < 2.7 else max(0, (3.0 - local) / 0.3))
        samples.append(0.5 * math.sin(phase) * window)
    return samples


def pulse() -> list[float]:
    samples: list[float] = []
    for i in range(SAMPLE_RATE * SECONDS):
        t = i / SAMPLE_RATE
        cycle = t % 0.5
        gate = 1.0 if cycle < 0.12 else 0.0
        square = 1.0 if tone(660, t) >= 0 else -1.0
        samples.append(0.35 * square * gate)
    return samples


def bell() -> list[float]:
    samples: list[float] = []
    for i in range(SAMPLE_RATE * SECONDS):
        t = i / SAMPLE_RATE
        local = t % 2.0
        note = 659.25 if local < 1.0 else 880.0
        inner = local if local < 1.0 else local - 1.0
        decay = math.exp(-1.3 * inner)
        mixed = tone(note, t) + 0.25 * tone(note * 2.01, t)
        samples.append(mixed * decay)
    return samples


def normalize(path: Path) -> None:
    """Target -9 LUFS and keep the true peak at or below -1 dBFS."""
    if shutil.which("ffmpeg") is None:
        peak_normalize(path)
        print(f"ffmpeg is not installed; peak-normalized {path.name} to -1 dBFS")
        return
    probe = subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-i", str(path),
            "-af", "loudnorm=I=-9:TP=-1.0:LRA=11:print_format=json",
            "-f", "null", "-",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    start = probe.stderr.rfind("{")
    end = probe.stderr.rfind("}")
    if start < 0 or end < start:
        peak_normalize(path)
        return
    measured = json.loads(probe.stderr[start:end + 1])
    temporary = path.with_suffix(".norm.wav")
    subprocess.run(
        [
            "ffmpeg", "-y", "-hide_banner", "-i", str(path),
            "-af",
            (
                "loudnorm=I=-9:TP=-1.0:LRA=11:linear=true:"
                f"measured_I={measured['input_i']}:"
                f"measured_TP={measured['input_tp']}:"
                f"measured_LRA={measured['input_lra']}:"
                f"measured_thresh={measured['input_thresh']}:"
                f"offset={measured['target_offset']}"
            ),
            "-ar", str(SAMPLE_RATE), "-ac", "1", "-c:a", "pcm_s16le",
            str(temporary),
        ],
        check=True,
        capture_output=True,
    )
    temporary.replace(path)


def peak_normalize(path: Path) -> None:
    ceiling = int(32767 * 10 ** (-1 / 20))
    with wave.open(str(path), "rb") as handle:
        frames = handle.readframes(handle.getnframes())
        params = handle.getparams()
    samples = list(struct.unpack("<" + "h" * (len(frames) // 2), frames))
    peak = max((abs(sample) for sample in samples), default=0)
    if peak == 0:
        return
    scale = ceiling / peak
    packed = struct.pack("<" + "h" * len(samples), *(max(-32767, min(32767, int(sample * scale))) for sample in samples))
    with wave.open(str(path), "wb") as handle:
        handle.setparams(params)
        handle.writeframes(packed)


def main() -> None:
    write_wav("classic.wav", classic())
    write_wav("chime.wav", chime())
    write_wav("rise.wav", rise())
    write_wav("pulse.wav", pulse())
    write_wav("bell.wav", bell())


if __name__ == "__main__":
    main()
