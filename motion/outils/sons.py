"""Synthesises Yumi's sounds. Original work, generated from the formulas below: nothing is
sampled or copied from another product.

    python3 outils/sons.py public/sons

Same 28 names as the app (`SoundEngine.preload()` in the Yumi repository), so the folder can
replace `Yumi/Resources/sounds` as it is. 44.1 kHz, 16 bit, mono. The output is deterministic.

The voice of the set: he is a small drop of slime, so everything he does is either a bubble
(a sine that slides, like a drop falling in water), a soft thumb-piano note in C major
pentatonic (no interval in it can sound sour, whatever follows whatever), or a little hum
when it is him speaking. Nothing buzzes, nothing is sharp, and a short room tail softens the ends.
"""

import sys
import wave
from pathlib import Path

import numpy as np

SR = 44100
rng = np.random.default_rng(7)

# C major pentatonic, in Hz
G4, A4 = 392.00, 440.00
C5, D5, E5, G5, A5 = 523.25, 587.33, 659.25, 783.99, 880.00
C6, D6, E6, G6, A6 = 1046.50, 1174.66, 1318.51, 1567.98, 1760.00
C7, D7, E7 = 2093.00, 2349.32, 2637.02


def times(dur):
    return np.arange(int(dur * SR)) / SR


def glide(f0, f1, over):
    """Exponential slide from f0 to f1 in `over` seconds, then steady."""
    return lambda t: f0 * (f1 / f0) ** np.minimum(1, t / over)


def steady(f):
    return lambda t: np.full_like(t, f)


def envelope(t, dur, attack, decay):
    """Rounded attack, exponential decay, and a short release so nothing clicks at the end."""
    a = np.sin(np.minimum(1, t / attack) * np.pi / 2) ** 2
    d = np.exp(-np.maximum(0, t - attack) / decay)
    r = np.clip((dur - t) / 0.012, 0, 1)
    return a * d * r


def tone(dur, freq, attack=0.006, decay=0.1, level=1.0, partials=((1, 1.0),)):
    """A pitched voice. The phase is accumulated, so slides are clean."""
    t = times(dur)
    phase = 2 * np.pi * np.cumsum(freq(t)) / SR
    s = sum(np.sin(phase * h) * a for h, a in partials)
    return s * envelope(t, dur, attack, decay) * level


def note(f, dur=0.45, decay=0.13, level=1.0):
    """A thumb-piano note: a round fundamental, a little octave, a wooden knock that dies at
    once, and a pitch that lands from slightly above, which is what makes it sound plucked."""
    t = times(dur)
    pitch = f * (1 + 0.035 * np.exp(-t / 0.012))
    phase = 2 * np.pi * np.cumsum(pitch) / SR
    body = np.sin(phase) * np.exp(-t / decay)
    octave = 0.22 * np.sin(2 * phase) * np.exp(-t / (decay * 0.5))
    twelfth = 0.06 * np.sin(3 * phase) * np.exp(-t / (decay * 0.3))
    knock = 0.10 * np.sin(5.4 * phase) * np.exp(-t / 0.012)
    attack = np.sin(np.minimum(1, t / 0.003) * np.pi / 2) ** 2
    release = np.clip((dur - t) / 0.012, 0, 1)
    return (body + octave + twelfth + knock) * attack * release * level


def bubble(f0, f1, dur=0.1, decay=0.035, level=1.0):
    """A drop in water: a pure tone that slides while it dies."""
    return tone(dur, glide(f0, f1, dur * 0.7), attack=0.003, decay=decay, level=level)


def hum(dur, freq, attack=0.03, decay=0.2, level=1.0, vibrato=0.0, rate=5.5):
    """His little voice: soft, slightly nasal, with a slow shake when he holds a sound."""
    f = lambda t: freq(t) * (1 + vibrato * np.sin(2 * np.pi * rate * t) * np.minimum(1, t / 0.12))
    return tone(dur, f, attack=attack, decay=decay, level=level,
                partials=((1, 1.0), (2, 0.28), (3, 0.10), (4, 0.03)))


def air(dur, cut0, cut1, attack=0.02, decay=0.08, level=1.0):
    """A breath: noise through a low-pass whose cutoff slides."""
    t = times(dur)
    x = rng.uniform(-1, 1, len(t))
    k = 1 - np.exp(-2 * np.pi * glide(cut0, cut1, dur)(t) / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += (x[i] - acc) * k[i]
        y[i] = acc
    return y * envelope(t, dur, attack, decay) * level


def mix(*parts):
    """Lays voices on a timeline: (start in seconds, samples)."""
    n = max(int(start * SR) + len(s) for start, s in parts)
    out = np.zeros(n)
    for start, s in parts:
        o = int(start * SR)
        out[o:o + len(s)] += s
    return out


def run(notes, gap, dur=0.4, decay=0.12, fade=1.0):
    """Notes one after the other, `gap` seconds apart, each `fade` times the level of the one before."""
    return mix(*[(i * gap, note(f, dur, decay, fade ** i)) for i, f in enumerate(notes)])


def room(x, amount=0.16):
    """A small soft room: four combs and two all-passes, low-passed, mixed in quietly."""
    tail = int(0.28 * SR)
    dry = np.concatenate([x, np.zeros(tail)])
    wet = np.zeros_like(dry)
    for delay, gain in ((1117, 0.70), (1361, 0.68), (1559, 0.66), (1783, 0.64)):
        y = dry.copy()
        for i in range(delay, len(y)):
            y[i] += gain * y[i - delay]
        wet += y / 4
    for delay, gain in ((241, 0.5), (83, 0.5)):
        y = np.zeros_like(wet)
        for i in range(len(wet)):
            back_x = wet[i - delay] if i >= delay else 0.0
            back_y = y[i - delay] if i >= delay else 0.0
            y[i] = -gain * wet[i] + back_x + gain * back_y
        wet = y
    # The tail is darker than the sound, and it fades to nothing
    acc = 0.0
    k = 1 - np.exp(-2 * np.pi * 3200 / SR)
    for i in range(len(wet)):
        acc += (wet[i] - acc) * k
        wet[i] = acc
    out = dry + amount * wet
    out[-tail:] *= np.linspace(1, 0, tail) ** 2
    return out


# (samples, loudness): 1 is a sound that wants to be heard, 0.5 one that should barely be noticed
SOUNDS = {
    # Island
    "peek":  (bubble(680, 1180, 0.09, 0.03), 0.55),
    "open":  (mix((0, bubble(330, 780, 0.2, 0.07)), (0, air(0.18, 500, 3500, level=0.12)),
                  (0.06, note(C6, 0.3, 0.08, 0.35))), 0.7),
    "close": (mix((0, note(G5, 0.25, 0.06, 0.35)), (0.02, bubble(700, 290, 0.2, 0.07)),
                  (0, air(0.16, 3000, 500, level=0.10))), 0.65),
    "hover": (note(E6, 0.12, 0.025), 0.3),
    "blip":  (note(A5, 0.22, 0.05), 0.55),
    "tick":  (note(G6, 0.08, 0.012), 0.4),
    "pop":   (mix((0, bubble(480, 1500, 0.07, 0.02)), (0.004, bubble(900, 300, 0.05, 0.012, 0.35))), 0.7),
    "send":  (mix((0, run([C5, E5, A5], 0.045, 0.28, 0.06)), (0, air(0.26, 600, 6000, 0.03, 0.09, 0.14))), 0.7),
    "attach": (mix((0, note(G6, 0.06, 0.01, 0.5)), (0.02, note(G5, 0.3, 0.07, 0.8)), (0.09, note(D6, 0.4, 0.1))), 0.7),
    "gulp":  (mix((0, bubble(440, 130, 0.2, 0.07)), (0.12, bubble(190, 420, 0.12, 0.035, 0.7))), 0.75),
    "approve": (mix((0, note(G5, 0.3, 0.07)), (0.075, note(C6, 0.5, 0.13)), (0.15, note(E7, 0.25, 0.05, 0.12))), 0.85),

    # States
    "work":   (run([E5, G5], 0.08, 0.26, 0.06, 0.8), 0.55),
    "think":  (mix((0, hum(0.36, glide(300, 345, 0.3), 0.05, 0.16, 0.5, 0.01)),
                   (0.05, run([E5, A5, G5], 0.14, 0.4, 0.11, 0.85))), 0.55),
    "search": (run([D6, D6, D6], 0.16, 0.4, 0.1, 0.42), 0.55),
    "approval": (mix((0, run([A5, D6], 0.13, 0.5, 0.13)), (0.5, run([A5, D6], 0.13, 0.5, 0.13, 1.0) * 0.4)), 0.9),
    "question": (mix((0, hum(0.3, glide(430, 660, 0.24), 0.02, 0.13, 0.8)), (0.2, note(E6, 0.35, 0.09, 0.45))), 0.75),
    # « Oh oh » in his voice, not a buzzer: an error should worry nobody
    "error":  (mix((0, hum(0.17, glide(415, 392, 0.12), 0.012, 0.09)),
                   (0.19, hum(0.36, glide(335, 294, 0.3), 0.012, 0.14)),
                   (0.19, note(D5, 0.4, 0.1, 0.25))), 0.85),
    "finish": (mix((0, run([C5, E5, G5], 0.085, 0.35, 0.09)), (0.255, note(C6, 0.7, 0.2)),
                   (0.34, note(G6, 0.4, 0.1, 0.2)), (0.42, note(E7, 0.4, 0.1, 0.12))), 0.9),
    "rate":   (mix((0, run([A5, E5], 0.16, 0.35, 0.09)), (0.32, note(C5, 0.55, 0.16)),
                   (0.32, bubble(520, 380, 0.3, 0.1, 0.25))), 0.7),
    "sleep":  (mix((0, hum(0.5, steady(G4), 0.06, 0.2, 0.7, 0.006, 4)), (0.36, hum(0.75, glide(340, 322, 0.6), 0.06, 0.28, 0.6, 0.006, 4)),
                   (0.36, note(C5, 0.6, 0.18, 0.2))), 0.5),
    "dizzy":  (mix((0, hum(0.75, lambda t: glide(640, 380, 0.7)(t) * (1 + 0.06 * np.sin(2 * np.pi * 9 * t)), 0.02, 0.32)),
                   (0.1, bubble(900, 1300, 0.06, 0.02, 0.3)), (0.3, bubble(700, 1100, 0.06, 0.02, 0.25)),
                   (0.48, bubble(560, 900, 0.06, 0.02, 0.2))), 0.7),

    # Character
    # Two syllables, the second one higher: « Yu-mi ! », with a little chord under it
    "greet":  (mix((0, hum(0.16, glide(560, 620, 0.1), 0.015, 0.08, 0.9)),
                   (0.15, hum(0.34, glide(760, 880, 0.08), 0.015, 0.16, 1.0, 0.008, 6)),
                   (0, note(C5, 0.4, 0.1, 0.35)), (0.15, note(G5, 0.5, 0.13, 0.35)), (0.23, note(E6, 0.6, 0.16, 0.3))), 0.9),
    # Jelly: a low thud that wobbles
    "slap":   (mix((0, tone(0.26, lambda t: glide(250, 120, 0.1)(t) * (1 + 0.10 * np.sin(2 * np.pi * 19 * t) * np.exp(-t / 0.09)),
                             0.002, 0.07)),
                   (0, air(0.05, 2500, 500, 0.001, 0.012, 0.3))), 0.75),
    "annoyed": (mix((0, hum(0.12, glide(330, 300, 0.1), 0.01, 0.06)), (0.12, hum(0.24, glide(270, 205, 0.2), 0.01, 0.1, 0.9))), 0.7),
    "love":   (mix((0, note(E5, 0.5, 0.14)), (0.13, note(A5, 0.6, 0.17)), (0.26, note(E6, 0.8, 0.22, 0.8)),
                   (0.3, hum(0.5, glide(600, 660, 0.3), 0.08, 0.2, 0.25, 0.012, 6))), 0.8),
    "proud":  (mix((0, run([G4, C5, E5], 0.07, 0.3, 0.08)), (0.21, note(G5, 0.7, 0.2)), (0.21, note(C6, 0.7, 0.2, 0.5))), 0.85),
    "wink":   (mix((0, note(G6, 0.3, 0.07)), (0.045, note(D7, 0.3, 0.07, 0.4))), 0.6),
    "yawn":   (hum(0.95, lambda t: 380 * (560 / 380) ** np.minimum(1, t / 0.3) * (250 / 560) ** np.clip((t - 0.3) / 0.6, 0, 1),
                   0.14, 0.42, 1.0, 0.012, 4.5), 0.6),
}


def write(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(pcm.tobytes())


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: python3 outils/sons.py <output folder>")
    folder = Path(sys.argv[1])
    folder.mkdir(parents=True, exist_ok=True)
    sheet = []
    for name, (samples, loudness) in SOUNDS.items():
        x = room(samples)
        # Mellow: nothing above 9 kHz matters in these sounds, and it is where harshness lives
        k = 1 - np.exp(-2 * np.pi * 9000 / SR)
        acc = 0.0
        for i in range(len(x)):
            acc += (x[i] - acc) * k
            x[i] = acc
        x *= 0.85 * loudness / np.max(np.abs(x))
        write(folder / f"{name}.wav", x)
        sheet += [x, np.zeros(int(0.45 * SR))]
        print(f"{name:9} {len(x) / SR:5.2f} s  peak {np.max(np.abs(x)):.2f}")
    # Every sound in a row, to listen to the whole set in one go
    write(folder / "_planche.wav", np.concatenate(sheet))
    print(f"{len(SOUNDS)} sounds written to {folder}")


if __name__ == "__main__":
    main()
