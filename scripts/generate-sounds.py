#!/usr/bin/env python3
"""Generate the bundled WakeMeUp alarm tones.

The tones are synthesized in this script (sine, square, and exponential decay).
No third-party recordings are included. Output is 16-bit PCM WAV, mono, 22.05 kHz,
about 12 seconds each, which is under Apple's 30-second custom-alert limit.

License: CC0 1.0 Universal. See WakeMeUp/Sounds/LICENSE.txt.
"""

from __future__ import annotations

import math
import struct
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
        decay = math.exp(-2.4 * local)
        mixed = sum(tone(freq, t) * amp for freq, amp in zip(partials, (0.5, 0.25, 0.15, 0.1)))
        samples.append(0.7 * mixed * decay)
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
        decay = math.exp(-3.2 * inner)
        mixed = tone(note, t) + 0.25 * tone(note * 2.01, t)
        samples.append(0.45 * mixed * decay)
    return samples


def main() -> None:
    write_wav("classic.wav", classic())
    write_wav("chime.wav", chime())
    write_wav("rise.wav", rise())
    write_wav("pulse.wav", pulse())
    write_wav("bell.wav", bell())


if __name__ == "__main__":
    main()
