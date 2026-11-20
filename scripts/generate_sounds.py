#!/usr/bin/env python3
"""Synthesize eight original Wakito alarm tones.

Nothing here is sampled from a recording, a system sound, or anyone else's
music. Each tone is sines, FM, and envelopes at 44.1 kHz. The shipped file is
mono Apple IMA4 in a CAF container (the MA4 format AlarmKit and notification
sounds accept). IMA4 is about a quarter of the size of 16-bit PCM, so eight
24 second tones stay under 5 MB.

The buffer length is a whole number of 64-sample IMA packets, which lands just
under 24 seconds. Loops are exact: repeating patterns tile the buffer, and the
two continuous tones use oscillators whose cycle count divides that length.

Requires numpy and ffmpeg to regenerate. `python3 scripts/generate_sounds.py --check`
only reads the committed CAF files and does not need either.

License: CC0 1.0 Universal. See WakeMeUp/Sounds/LICENSE.txt.
"""

from __future__ import annotations

import math
import struct
import subprocess
import sys
import wave
from pathlib import Path

np = None  # Imported only when regenerating. --check stays on the standard library.

SR = 44100
# 24 s of 44.1 kHz, trimmed to a whole number of IMA4 packets (64 frames).
N = (24 * SR // 64) * 64
ROOT = Path(__file__).resolve().parents[1] / "WakeMeUp" / "Sounds"
# -1 dBFS is the alarm ceiling. Stay a little under it so IMA4 does not clip.
PEAK = 0.84
# -9 dB mean square, the same loudness target as AlarmLoudness in the app.
TARGET_MEAN_SQUARE = 0.12589254
NAMES = (
    "dawn",
    "beep",
    "bells",
    "digital",
    "morning",
    "birds",
    "marimba",
    "sleepy",
)


def sine_cycles(cycles: int, n: int | None = None) -> np.ndarray:
    count = N if n is None else n
    i = np.arange(count, dtype=np.float64)
    return np.sin(2 * math.pi * cycles * i / N)


def place(buffer: np.ndarray, start: int, clip: np.ndarray) -> None:
    start = int(start)
    end = start + len(clip)
    if start < 0 or end > len(buffer):
        raise RuntimeError(f"clip {start}:{end} does not fit in {len(buffer)}")
    buffer[start:end] += clip


def edge(n: int, attack: float, release: float) -> np.ndarray:
    env = np.ones(n, dtype=np.float64)
    a = min(n // 4, max(1, int(attack * SR)))
    r = min(n // 4, max(1, int(release * SR)))
    env[:a] = np.linspace(0, 1, a, endpoint=False)
    env[-r:] = np.linspace(1, 0, r)
    return env


def normalize(samples: np.ndarray) -> np.ndarray:
    peak = float(np.max(np.abs(samples)))
    mean_square = float(np.mean(samples * samples))
    if peak == 0 or mean_square == 0:
        raise RuntimeError("synthesis produced silence")
    gain = min(PEAK / peak, math.sqrt(TARGET_MEAN_SQUARE / mean_square))
    out = samples * gain
    limit = float(np.max(np.abs(out)))
    if limit > PEAK + 1e-6:
        raise RuntimeError(f"peak {limit} exceeded the ceiling")
    return out


def tile(cell: np.ndarray, times: int) -> np.ndarray:
    if len(cell) * times != N:
        raise RuntimeError(f"cell {len(cell)} * {times} != {N}")
    return np.tile(cell, times)


def dawn() -> np.ndarray:
    """Warm pad that swells and falls back, with a few soft chimes."""
    i = np.arange(N, dtype=np.float64)
    swell = 0.34 + 0.66 * 0.5 * (1 - np.cos(2 * math.pi * i / N))
    # Integer cycle counts over the whole buffer, near G3 / B3 / D4 / G4 / G2.
    pad = (
        0.34 * sine_cycles(4704)
        + 0.26 * sine_cycles(5928)
        + 0.16 * sine_cycles(7056)
        + 0.10 * sine_cycles(9408)
        + 0.08 * sine_cycles(2352)
        + 0.06 * sine_cycles(4708)
    )
    tone = pad * swell
    for start, freq in ((4.0, 1568.0), (10.0, 1976.0), (16.0, 2349.0)):
        length = int(1.15 * SR)
        t = np.arange(length) / SR
        chime = np.sin(2 * math.pi * freq * t) * np.exp(-2.4 * t)
        chime += 0.35 * np.sin(2 * math.pi * freq * 2.76 * t) * np.exp(-3.6 * t)
        chime *= edge(length, 0.01, 0.05)
        place(tone, int(start * SR), 0.22 * chime)
    return tone


def buzz(freq: float, dur: float, amp: float) -> np.ndarray:
    n = max(8, int(dur * SR))
    t = np.arange(n) / SR
    partials = (1.0, 0.45, 0.22, 0.1)
    wave_sum = np.zeros(n, dtype=np.float64)
    for k, weight in enumerate(partials, start=1):
        wave_sum += weight * np.sin(2 * math.pi * freq * k * t)
    click_n = min(n, int(0.012 * SR))
    click = np.sin(2 * math.pi * 180 * t[:click_n]) * np.linspace(1, 0, click_n)
    wave_sum[:click_n] += 0.55 * click
    return amp * wave_sum * edge(n, 0.004, 0.018)


def beep() -> np.ndarray:
    """Two short digital beeps, then a rest. The rest makes the loop seamless."""
    cell = np.zeros(N // 23, dtype=np.float64)
    place(cell, int(0.02 * SR), buzz(880, 0.16, 0.95))
    place(cell, int(0.26 * SR), buzz(988, 0.16, 0.95))
    return tile(cell, 23)


def fm_bell(freq: float, dur: float) -> np.ndarray:
    n = int(dur * SR)
    t = np.arange(n) / SR
    index = 3.2 * np.exp(-5.5 * t)
    modulator = index * np.sin(2 * math.pi * freq * 2 * t)
    bell = np.sin(2 * math.pi * freq * t + modulator) * np.exp(-2.4 * t)
    bell += 0.18 * np.sin(2 * math.pi * freq * 2.76 * t) * np.exp(-4.2 * t)
    return bell * edge(n, 0.004, 0.04)


def bells() -> np.ndarray:
    """A short original chime arpeggio on a 3 second loop."""
    phrases = (
        (523.25, 659.25, 783.99, 1046.50),
        (1046.50, 783.99, 659.25, 523.25),
        (659.25, 783.99, 987.77, 1318.51),
        (523.25, 783.99, 1046.50, 1567.98),
    )
    cell_n = N // 8
    tone = np.zeros(N, dtype=np.float64)
    for index in range(8):
        cell = np.zeros(cell_n, dtype=np.float64)
        for step, freq in enumerate(phrases[index % len(phrases)]):
            place(cell, int((0.06 + step * 0.70) * SR), fm_bell(freq, 0.62))
        tone[index * cell_n:(index + 1) * cell_n] = cell
    return tone


def digital() -> np.ndarray:
    """A detuned pulsing synth. Every oscillator closes after exactly N samples."""
    i = np.arange(N, dtype=np.float64)
    lfo = 0.5 + 0.5 * np.sin(2 * math.pi * 46 * i / N)
    fund = 2640  # ~110 Hz, an integer number of cycles
    tone = np.zeros(N, dtype=np.float64)
    for k in range(1, 8):
        brightness = 1.0 if k == 1 else (0.22 + 0.78 * lfo)
        tone += (brightness / k) * sine_cycles(fund * k)
    tone *= 0.58 + 0.42 * lfo
    pos = (i * 23 / N) % 1.0
    duty = 0.20
    bump = np.zeros(N, dtype=np.float64)
    on = pos < duty
    bump[on] = 0.5 - 0.5 * np.cos(2 * math.pi * pos[on] / duty)
    tone += 0.55 * bump * sine_cycles(fund * 2)
    tone += 0.12 * sine_cycles(1320)
    return tone


def soft_note(freq: float, n: int) -> np.ndarray:
    t = np.arange(n) / SR
    voice = np.sin(2 * math.pi * freq * t)
    voice += 0.16 * np.sin(2 * math.pi * freq * 2 * t)
    voice += 0.05 * np.sin(2 * math.pi * freq * 3 * t)
    voice += 0.04 * np.sin(2 * math.pi * (freq * 1.002) * t)
    return voice * np.exp(-1.5 * t) * edge(n, 0.015, 0.06)


def morning() -> np.ndarray:
    """An original six-note pentatonic phrase. Two shapes alternate."""
    phrase_a = (659.25, 783.99, 880.00, 783.99, 659.25, 587.33)
    phrase_b = (523.25, 587.33, 659.25, 783.99, 659.25, 523.25)
    cell_n = N // 8
    slot = cell_n // 6
    tone = np.zeros(N, dtype=np.float64)
    for index in range(8):
        notes = phrase_a if index % 2 == 0 else phrase_b
        cell = np.zeros(cell_n, dtype=np.float64)
        length = int(slot * 0.90)
        for step, freq in enumerate(notes):
            place(cell, step * slot, soft_note(freq, length))
        tone[index * cell_n:(index + 1) * cell_n] = cell
    return tone


def chirp(f0: float, f1: float, dur: float, amp: float) -> np.ndarray:
    n = int(dur * SR)
    u = np.arange(n) / SR
    phase = 2 * math.pi * (f0 * u + (f1 - f0) * u * u / (2 * dur))
    window = np.sin(math.pi * np.arange(n) / n) ** 1.15
    voice = np.sin(phase) + 0.22 * np.sin(2 * phase)
    return amp * voice * window


def coo(dur: float, amp: float) -> np.ndarray:
    n = int(dur * SR)
    t = np.arange(n) / SR
    vibrato = 14 * np.sin(2 * math.pi * 4.5 * t)
    phase = 2 * math.pi * np.cumsum(640 + vibrato) / SR
    window = np.sin(math.pi * np.arange(n) / n) ** 1.4
    voice = np.sin(phase) + 0.18 * np.sin(2 * phase)
    return amp * voice * window


def birds() -> np.ndarray:
    """Seeded, hand-placed chirps in a 6 second cell. No recordings."""
    events = (
        (0.40, chirp(2300, 3600, 0.09, 0.55)),
        (0.55, chirp(3400, 2700, 0.07, 0.38)),
        (0.85, chirp(1900, 4300, 0.12, 0.60)),
        (1.25, chirp(3600, 4100, 0.05, 0.34)),
        (1.40, chirp(3900, 3000, 0.08, 0.40)),
        (1.70, chirp(2500, 4600, 0.10, 0.50)),
        (2.25, coo(0.38, 0.42)),
        (3.05, chirp(2100, 3300, 0.11, 0.48)),
        (3.35, chirp(3200, 2400, 0.08, 0.36)),
        (3.70, chirp(2600, 4800, 0.12, 0.58)),
        (4.15, chirp(4200, 3500, 0.06, 0.32)),
        (4.45, chirp(2800, 3900, 0.09, 0.46)),
        (4.80, chirp(2000, 3100, 0.13, 0.44)),
        (5.20, chirp(3400, 2600, 0.08, 0.30)),
    )
    cell_n = N // 4
    cell = np.zeros(cell_n, dtype=np.float64)
    for start, clip in events:
        place(cell, int(start * SR), clip)
    return tile(cell, 4)


def mallet(freq: float, dur: float) -> np.ndarray:
    n = int(dur * SR)
    t = np.arange(n) / SR
    modulator = np.sin(2 * math.pi * freq * 3.1 * t) * np.exp(-16 * t) * 2.0
    carrier = np.sin(2 * math.pi * freq * t + modulator) * np.exp(-3.3 * t)
    knock = np.sin(2 * math.pi * freq * 6.8 * t) * np.exp(-28 * t) * 0.28
    return (carrier + knock) * edge(n, 0.002, 0.03)


def marimba() -> np.ndarray:
    """Wooden FM notes on an original ostinato."""
    pattern = (261.63, 392.00, 523.25, 329.63, 440.00, 392.00, 329.63)
    times = (0.02, 0.38, 0.74, 1.16, 1.52, 1.96, 2.40)
    cell_n = N // 8
    cell = np.zeros(cell_n, dtype=np.float64)
    for start, freq in zip(times, pattern):
        place(cell, int(start * SR), mallet(freq, 0.42))
    return tile(cell, 8)


def sleepy() -> np.ndarray:
    """Loud beeps that speed up and step higher, over a tone that swells with them."""
    cell_n = N // 8
    cell_dur = cell_n / SR
    cell = np.zeros(cell_n, dtype=np.float64)
    t = np.arange(cell_n) / SR
    # Zero at both ends of the phrase, so the loop does not click.
    swell = np.sin(math.pi * np.arange(cell_n) / cell_n) ** 1.15
    bed = np.sin(2 * math.pi * 146.83 * t) + 0.45 * np.sin(2 * math.pi * 293.66 * t)
    cell += 0.34 * bed * swell
    count = 9
    start = 0.05
    end = cell_dur - 0.20
    u = np.linspace(0, 1, count)
    positions = start + (end - start) * (1 - (1 - u) ** 2.2)
    freqs = (523.25, 587.33, 659.25, 739.99, 830.61, 932.33, 1046.50, 1174.66, 1318.51)
    for index, (pos, freq) in enumerate(zip(positions, freqs)):
        amp = 0.82 + 0.18 * (index / (count - 1))
        dur = 0.13 - 0.045 * (index / (count - 1))
        place(cell, int(float(pos) * SR), buzz(float(freq), float(dur), float(amp)))
    return tile(cell, 8)


SYNTHESIZERS = {
    "dawn": dawn,
    "beep": beep,
    "bells": bells,
    "digital": digital,
    "morning": morning,
    "birds": birds,
    "marimba": marimba,
    "sleepy": sleepy,
}


def write_caf(name: str, samples: np.ndarray) -> Path:
    samples = normalize(samples)
    if len(samples) != N:
        raise RuntimeError(f"{name} has {len(samples)} samples, expected {N}")
    ROOT.mkdir(parents=True, exist_ok=True)
    destination = ROOT / f"{name}.caf"
    temporary = ROOT / f".{name}.wav"
    pcm = np.clip(np.round(samples * 32767), -32767, 32767).astype(np.int16)
    with wave.open(str(temporary), "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(pcm.tobytes())
    if subprocess.call(["ffmpeg", "-version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) != 0:
        temporary.unlink(missing_ok=True)
        raise SystemExit("ffmpeg is required to pack IMA4 CAF files")
    subprocess.run(
        [
            "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
            "-i", str(temporary),
            "-c:a", "adpcm_ima_qt",
            "-ar", str(SR),
            "-ac", "1",
            str(destination),
        ],
        check=True,
    )
    temporary.unlink()
    decoded = decode(destination)
    peak = float(np.max(np.abs(decoded)))
    seam = abs(float(decoded[0]) - float(decoded[-1]))
    duration = len(decoded) / SR
    print(
        f"wrote {destination.name}: {destination.stat().st_size} bytes, "
        f"{duration:.3f}s, peak {peak:.3f}, seam {seam:.4f}"
    )
    if not 20 <= duration <= 30:
        raise RuntimeError(f"{name} duration {duration} is outside 20–30 s")
    if peak > 0.98:
        raise RuntimeError(f"{name} peaks at {peak}, which will clip")
    if seam > 0.03:
        raise RuntimeError(f"{name} loop seam is {seam}")
    return destination


def decode(path: Path) -> np.ndarray:
    raw = subprocess.check_output(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-i", str(path),
            "-f", "s16le", "-ac", "1", "-ar", str(SR),
            "-",
        ]
    )
    return np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0


def read_caf_header(path: Path) -> tuple[float, int]:
    data = path.read_bytes()
    if data[:4] != b"caff":
        raise RuntimeError(f"{path.name} is not a CAF file")
    offset = 8
    sample_rate = 0.0
    frames = 0
    while offset + 12 <= len(data):
        kind = data[offset:offset + 4]
        size = struct.unpack_from(">q", data, offset + 4)[0]
        body = offset + 12
        if kind == b"desc":
            sample_rate, fmt, _flags, bpf, fpp, channels, _bits = struct.unpack_from(
                ">dIIiiII", data, body
            )
            fourcc = fmt.to_bytes(4, "big")
            if fourcc != b"ima4" or channels != 1 or bpf != 34 or fpp != 64:
                raise RuntimeError(f"{path.name} is not mono 44.1 kHz-ready IMA4 ({fourcc!r})")
            if abs(sample_rate - SR) > 0.1:
                raise RuntimeError(f"{path.name} sample rate is {sample_rate}")
        elif kind == b"data":
            payload = size - 4  # leading edit count
            if payload % 34 != 0:
                raise RuntimeError(f"{path.name} IMA data is not a whole number of packets")
            frames = (payload // 34) * 64
        if size < 0:
            break
        offset = body + size
    if frames == 0:
        raise RuntimeError(f"{path.name} has no audio data")
    return sample_rate, frames


def check() -> None:
    total = 0
    for name in NAMES:
        path = ROOT / f"{name}.caf"
        if not path.is_file():
            raise SystemExit(f"missing {path}")
        _rate, frames = read_caf_header(path)
        duration = frames / SR
        if not 20 <= duration <= 30:
            raise SystemExit(f"{name} is {duration:.3f}s, expected 20–30 s")
        total += path.stat().st_size
        print(f"{name}.caf {duration:.3f}s {path.stat().st_size} bytes")
    if total >= 5_000_000:
        raise SystemExit(f"new sounds are {total} bytes, over the 5 MB budget")
    print(f"{len(NAMES)} sounds, {total} bytes")


def main() -> None:
    if "--check" in sys.argv:
        check()
        return
    global np
    import numpy as np
    written: list[Path] = []
    for name, synthesize in SYNTHESIZERS.items():
        written.append(write_caf(name, synthesize()))
    total = sum(path.stat().st_size for path in written)
    if total >= 5_000_000:
        raise SystemExit(f"new sounds are {total} bytes, over the 5 MB budget")
    print(f"total {total} bytes")


if __name__ == "__main__":
    main()
