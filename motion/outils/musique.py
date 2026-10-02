"""Synthesises the music of the film. Original work, generated from the formulas below:
nothing is sampled or copied.

    python3 outils/musique.py public/musique/ambiance.wav

27.6 s, the length of the film, 44.1 kHz, 16 bit, stereo. It follows the film:

    0 to 2 s    the dark: one low held chord, barely there
    2 s         the light comes on: the chord opens, a slow thumb-piano pattern starts
    2 to 24 s   four calm chords that turn (C, A minor, F, G), 96 beats a minute
    26.6 s      he falls asleep: the pattern stops, the held chord of the start comes back

It is in C, and avoids the note B, so every one of Yumi's sounds (outils/sons.py, C major
pentatonic) is in tune with whatever chord it falls on.
"""

import sys
import wave
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from sons import SR, note  # noqa: E402

LENGTH = 27.6
LIGHT = 2.0
NIGHT = 26.6
BAR = 2.5  # four beats at 96 a minute
N = int(LENGTH * SR)
t = np.arange(N) / SR

# Notes (Hz)
F2, G2, A2 = 87.31, 98.00, 110.00
C3, D3, E3, G3, A3 = 130.81, 146.83, 164.81, 196.00, 220.00
C4, D4, E4 = 261.63, 293.66, 329.63
C5, D5, E5, G5, A5, C6 = 523.25, 587.33, 659.25, 783.99, 880.00, 1046.50
F5 = 698.46

# (held notes, pattern of eight notes) for each bar after the light comes on
C = ([C3, G3, D4, E4], [C5, G5, E5, G5, D5, G5, E5, C6])
Am = ([A2, E3, C4, E4], [A5, E5, C5, E5, A5, E5, C6, E5])
F = ([F2, C3, A3, E4], [F5, C5, A5, C5, E5, C5, A5, C6])
G = ([G2, D3, A3, D4], [G5, D5, A5, D5, G5, D5, A5, D5])
BARS = [C, Am, F, G, C, Am, F, G, C, F]


def smooth(x, a, b):
    """0 before a, 1 after b, a soft S in between."""
    p = np.clip((x - a) / (b - a), 0, 1)
    return p * p * (3 - 2 * p)


def pad(freqs, start, end, level=1.0, attack=1.0, release=1.4):
    """A held chord: for each note two sines a hair apart, one in each ear, so it shimmers slowly."""
    env = smooth(t, start, start + attack) * (1 - smooth(t, end, end + release)) * level
    left = np.zeros(N)
    right = np.zeros(N)
    for i, f in enumerate(freqs):
        # Higher notes are quieter: the chord stays warm
        gain = 1 / (1 + i * 0.35)
        for ear, detune in ((left, -1), (right, 1)):
            w = 2 * np.pi * f * (1 + detune * 0.0016) * t
            ear += gain * (np.sin(w) + 0.10 * np.sin(2 * w + i) + 0.04 * np.sin(3 * w))
    return np.stack([left * env, right * env])


def place(track, at, samples, level, pan):
    """Adds a mono sound to the stereo track; pan 0 is left, 1 is right."""
    o = int(at * SR)
    n = min(len(samples), N - o)
    if n <= 0:
        return
    track[0, o:o + n] += samples[:n] * level * np.cos(pan * np.pi / 2)
    track[1, o:o + n] += samples[:n] * level * np.sin(pan * np.pi / 2)


def feedback(y, delay, gain):
    """y[n] += gain * y[n - delay], a block of `delay` samples at a time."""
    for k in range(delay, len(y), delay):
        block = y[k:k + delay]
        block += gain * y[k - delay:k - delay + len(block)]
    return y


def lowpass(x, cutoff):
    """A gentle 6 dB per octave slope, without shifting anything in time."""
    spectrum = np.fft.rfft(x)
    f = np.fft.rfftfreq(x.shape[-1], 1 / SR)
    return np.fft.irfft(spectrum / np.sqrt(1 + (f / cutoff) ** 2), x.shape[-1])


def room(x, amount):
    """A soft room on one channel: four combs, two all-passes, a dark tail."""
    wet = np.zeros_like(x)
    for delay, gain in ((1557, 0.80), (1617, 0.79), (1491, 0.81), (1277, 0.82)):
        wet += feedback(x.copy(), delay, gain) / 4
    for delay, gain in ((225, 0.6), (556, 0.6)):
        y = -gain * wet
        y[delay:] += wet[:-delay]
        wet = feedback(y, delay, gain)
    return x + amount * lowpass(wet, 2600)


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: python3 outils/musique.py <output file>")
    track = np.zeros((2, N))

    # The dark, at both ends of the film: a low fifth, so the loop closes on what it opened with
    track += pad([C3, G3], -2, LIGHT + 0.3, 0.32, attack=0.1, release=2.0)
    track += pad([C3, G3], NIGHT - 0.4, LENGTH + 2, 0.32, attack=1.2)

    for i, (held, pattern) in enumerate(BARS):
        start = LIGHT + i * BAR
        end = min(start + BAR, NIGHT)
        # The first chord blooms faster: it is the light coming on
        track += pad(held, start - 0.3, end - 0.5, 0.42, attack=0.6 if i == 0 else 1.1)
        # A soft low root under each chord
        root = held[0] / 2 if held[0] > 100 else held[0]
        track += pad([root], start - 0.2, end - 0.6, 0.30, attack=0.8)
        for j, f in enumerate(pattern):
            at = start + j * BAR / 8
            if at > NIGHT - 0.5:
                break
            # The pattern comes in over the first bar, leans on the first and fifth notes,
            # and wanders from one ear to the other
            level = 0.20 * (1.0 if j % 4 == 0 else 0.62) * smooth(np.array(at), LIGHT - 0.5, LIGHT + BAR)
            place(track, at, note(f, 1.4, 0.32), level, 0.5 + 0.28 * np.sin(j * 2.4 + i))

    # The light itself: two high notes that ring
    place(track, LIGHT, note(E5 * 2, 2.2, 0.6), 0.10, 0.35)
    place(track, LIGHT + 0.16, note(G5 * 2, 2.2, 0.6), 0.08, 0.65)

    out = np.stack([room(track[0], 0.30), room(track[1], 0.30)])
    out = lowpass(out, 7000)
    out *= smooth(t, 0, 0.35) * (1 - smooth(t, LENGTH - 0.7, LENGTH))
    out *= 0.6 / np.max(np.abs(out))

    path = Path(sys.argv[1])
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes((out.T * 32767).astype("<i2").tobytes())
    rms = np.sqrt((out ** 2).mean())
    print(f"{path}: {LENGTH} s, peak {np.max(np.abs(out)):.2f}, rms {rms:.3f}")


if __name__ == "__main__":
    main()
