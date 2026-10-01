// Synthesises the 28 placeholder sounds of Yumi. Original work, generated from the formulas
// below: nothing is sampled or copied from another product.
//
//   swift design/yumi/outils/sons.swift Yumi/Resources/sounds
//
// File names are the ones SoundEngine.preload() looks for. 44.1 kHz, 16 bit, mono.
// The output is deterministic (seeded noise), so running it twice gives identical files.

import Foundation

let sampleRate = 44100.0

// MARK: - Building blocks

typealias Samples = [Double]

/// Deterministic white noise in -1…1.
struct Noise {
    var seed: UInt32
    mutating func next() -> Double {
        seed = seed &* 1664525 &+ 1013904223
        return Double(seed >> 8) / Double(1 << 23) - 1
    }
}

/// Linear attack, exponential decay, short release so nothing clicks at the end.
func envelope(_ t: Double, dur: Double, attack: Double, decay: Double) -> Double {
    let a = min(1, t / attack)
    let d = exp(-max(0, t - attack) / decay)
    let r = min(1, (dur - t) / 0.008)
    return a * d * max(0, r)
}

/// A pitched voice. `freq` is evaluated at every sample (phase is accumulated, so glides are clean).
/// `partials` are (harmonic, level) pairs.
func voice(dur: Double, attack: Double = 0.004, decay: Double, level: Double = 1,
           partials: [(Double, Double)] = [(1, 1)], freq: (Double) -> Double) -> Samples {
    let n = Int(dur * sampleRate)
    var phase = 0.0
    var out = Samples(repeating: 0, count: n)
    for i in 0..<n {
        let t = Double(i) / sampleRate
        phase += 2 * .pi * freq(t) / sampleRate
        var s = 0.0
        for (h, a) in partials { s += sin(phase * h) * a }
        out[i] = s * envelope(t, dur: dur, attack: attack, decay: decay) * level
    }
    return out
}

/// Noise through a one-pole low-pass whose cutoff can move.
func noise(dur: Double, attack: Double = 0.002, decay: Double, level: Double = 1, seed: UInt32,
           cutoff: (Double) -> Double) -> Samples {
    let n = Int(dur * sampleRate)
    var gen = Noise(seed: seed)
    var y = 0.0
    var out = Samples(repeating: 0, count: n)
    for i in 0..<n {
        let t = Double(i) / sampleRate
        let k = 1 - exp(-2 * .pi * cutoff(t) / sampleRate)
        y += (gen.next() - y) * k
        out[i] = y * envelope(t, dur: dur, attack: attack, decay: decay) * level
    }
    return out
}

/// Lays voices on a timeline: (start in seconds, samples).
func mix(_ parts: [(Double, Samples)]) -> Samples {
    let n = parts.map { Int($0.0 * sampleRate) + $0.1.count }.max() ?? 0
    var out = Samples(repeating: 0, count: n)
    for (start, s) in parts {
        let o = Int(start * sampleRate)
        for i in 0..<s.count { out[o + i] += s[i] }
    }
    return out
}

func glide(_ f0: Double, _ f1: Double, over dur: Double) -> (Double) -> Double {
    { t in f0 * pow(f1 / f0, min(1, t / dur)) }
}

func steady(_ f: Double) -> (Double) -> Double { { _ in f } }

func vibrato(_ f: @escaping (Double) -> Double, rate: Double, depth: Double) -> (Double) -> Double {
    { t in f(t) * (1 + depth * sin(2 * .pi * rate * t)) }
}

let soft: [(Double, Double)] = [(1, 1), (2, 0.18)]
let bell: [(Double, Double)] = [(1, 1), (2, 0.35), (3, 0.12), (4.2, 0.06)]
let buzz: [(Double, Double)] = [(1, 1), (2, 0.5), (3, 0.33), (4, 0.25), (5, 0.2)]

/// A short bell note.
func ping(_ f: Double, dur: Double = 0.22, decay: Double = 0.07, level: Double = 1) -> Samples {
    voice(dur: dur, decay: decay, level: level, partials: bell, freq: steady(f))
}

// Notes (Hz)
let C4 = 261.63, E4 = 329.63, G4 = 392.00, A4 = 440.00
let C5 = 523.25, D5 = 587.33, E5 = 659.25, G5 = 783.99, A5 = 880.00
let C6 = 1046.50, D6 = 1174.66, E6 = 1318.51, G6 = 1567.98

// MARK: - The 28 sounds

let sounds: [(String, Samples)] = [
    // Island
    ("peek",  voice(dur: 0.11, decay: 0.04, partials: soft, freq: glide(620, 930, over: 0.08))),
    ("open",  mix([(0, voice(dur: 0.20, decay: 0.08, partials: soft, freq: glide(300, 720, over: 0.16))),
                   (0, noise(dur: 0.16, decay: 0.05, level: 0.25, seed: 11, cutoff: glide(600, 4000, over: 0.14)))])),
    ("close", mix([(0, voice(dur: 0.18, decay: 0.07, partials: soft, freq: glide(640, 270, over: 0.14))),
                   (0, noise(dur: 0.14, decay: 0.04, level: 0.2, seed: 12, cutoff: glide(3500, 500, over: 0.12)))])),
    ("hover", voice(dur: 0.05, attack: 0.002, decay: 0.012, partials: soft, freq: steady(1250))),
    ("blip",  voice(dur: 0.09, attack: 0.002, decay: 0.03, partials: soft, freq: steady(A5))),
    ("tick",  mix([(0, noise(dur: 0.012, attack: 0.0005, decay: 0.003, level: 0.6, seed: 13, cutoff: steady(7000))),
                   (0, voice(dur: 0.03, attack: 0.001, decay: 0.008, freq: steady(1850)))])),
    ("pop",   voice(dur: 0.08, attack: 0.001, decay: 0.022, partials: soft, freq: glide(950, 280, over: 0.05))),
    ("send",  mix([(0, noise(dur: 0.26, attack: 0.03, decay: 0.09, level: 0.5, seed: 14, cutoff: glide(500, 6500, over: 0.22))),
                   (0.02, voice(dur: 0.22, decay: 0.08, level: 0.7, partials: soft, freq: glide(420, 1250, over: 0.2)))])),
    ("attach", mix([(0, noise(dur: 0.02, attack: 0.0005, decay: 0.005, level: 0.7, seed: 15, cutoff: steady(5000))),
                    (0.01, ping(G5, dur: 0.1, decay: 0.03, level: 0.8)),
                    (0.07, ping(D6, dur: 0.14, decay: 0.045))])),
    ("gulp",  mix([(0, voice(dur: 0.2, attack: 0.006, decay: 0.07, partials: soft, freq: glide(430, 110, over: 0.13))),
                   (0.11, voice(dur: 0.1, attack: 0.004, decay: 0.03, level: 0.6, partials: soft, freq: glide(160, 330, over: 0.06)))])),
    ("approve", mix([(0, ping(G5, dur: 0.12, decay: 0.035)), (0.07, ping(C6, dur: 0.2, decay: 0.06))])),

    // States
    ("work",   mix([(0, ping(C5, dur: 0.1, decay: 0.03, level: 0.8)), (0.09, ping(C5, dur: 0.12, decay: 0.035, level: 0.6))])),
    ("think",  mix([(0, ping(E5, dur: 0.14, decay: 0.04, level: 0.6)), (0.13, ping(A5, dur: 0.14, decay: 0.04, level: 0.5)),
                    (0.3, ping(G5, dur: 0.2, decay: 0.06, level: 0.45))])),
    ("search", mix([(0, voice(dur: 0.42, attack: 0.003, decay: 0.13, partials: soft, freq: steady(1020))),
                    (0.16, voice(dur: 0.3, attack: 0.003, decay: 0.1, level: 0.3, partials: soft, freq: steady(1020)))])),
    ("approval", mix([(0, ping(A5, dur: 0.2, decay: 0.07)), (0.14, ping(D6, dur: 0.34, decay: 0.11))])),
    ("question", voice(dur: 0.3, decay: 0.11, partials: bell, freq: glide(520, 790, over: 0.2))),
    ("error",  mix([(0, voice(dur: 0.17, decay: 0.07, partials: buzz, freq: steady(E4))),
                    (0.15, voice(dur: 0.28, decay: 0.1, partials: buzz, freq: steady(C4 * 0.97)))])),
    ("finish", mix([(0, ping(C5, dur: 0.16, decay: 0.05)), (0.09, ping(E5, dur: 0.16, decay: 0.05)),
                    (0.18, ping(G5, dur: 0.16, decay: 0.05)), (0.27, ping(C6, dur: 0.42, decay: 0.14))])),
    ("rate",   mix([(0, ping(A5, dur: 0.12, decay: 0.04)), (0.13, ping(E5, dur: 0.12, decay: 0.04)),
                    (0.26, ping(C5, dur: 0.24, decay: 0.08))])),
    ("sleep",  mix([(0, voice(dur: 0.4, attack: 0.03, decay: 0.16, partials: soft, freq: steady(G4))),
                    (0.3, voice(dur: 0.55, attack: 0.03, decay: 0.2, level: 0.8, partials: soft, freq: steady(E4)))])),
    ("dizzy",  voice(dur: 0.7, attack: 0.01, decay: 0.3, partials: soft,
                     freq: vibrato(glide(620, 360, over: 0.65), rate: 11, depth: 0.07))),

    // Character
    ("greet",  mix([(0, ping(C5, dur: 0.16, decay: 0.05)), (0.1, ping(G5, dur: 0.16, decay: 0.05)),
                    (0.2, ping(E6, dur: 0.36, decay: 0.12))])),
    ("slap",   mix([(0, noise(dur: 0.09, attack: 0.0005, decay: 0.018, seed: 16, cutoff: glide(5000, 900, over: 0.05))),
                    (0, voice(dur: 0.12, attack: 0.001, decay: 0.03, level: 0.9, freq: glide(210, 85, over: 0.08)))])),
    ("annoyed", voice(dur: 0.26, attack: 0.006, decay: 0.11, partials: buzz, freq: glide(310, 205, over: 0.2))),
    ("love",   mix([(0, voice(dur: 0.24, decay: 0.09, partials: bell, freq: vibrato(steady(E5), rate: 7, depth: 0.012))),
                    (0.14, voice(dur: 0.42, decay: 0.15, partials: bell, freq: vibrato(steady(A5), rate: 7, depth: 0.012)))])),
    ("proud",  mix([(0, ping(G4, dur: 0.13, decay: 0.045)), (0.08, ping(C5, dur: 0.13, decay: 0.045)),
                    (0.16, ping(E5, dur: 0.13, decay: 0.045)), (0.24, ping(G5, dur: 0.4, decay: 0.13))])),
    ("wink",   ping(G6, dur: 0.16, decay: 0.04)),
    ("yawn",   voice(dur: 0.8, attack: 0.12, decay: 0.32, partials: soft,
                     freq: vibrato(glide(540, 250, over: 0.75), rate: 4.5, depth: 0.02))),
]

// MARK: - WAV output

func wav(_ samples: Samples) -> Data {
    // Same loudness for all: peak at 0.85 of full scale (the app plays them at a low volume).
    let peak = samples.map { abs($0) }.max() ?? 1
    let gain = peak > 0 ? 0.85 / peak : 0
    var pcm = Data(capacity: samples.count * 2)
    for s in samples {
        let v = Int16(max(-1, min(1, s * gain)) * 32767)
        withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
    }
    func le<T: FixedWidthInteger>(_ v: T) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    var d = Data()
    d.append("RIFF".data(using: .ascii)!); d.append(le(UInt32(36 + pcm.count))); d.append("WAVE".data(using: .ascii)!)
    d.append("fmt ".data(using: .ascii)!); d.append(le(UInt32(16))); d.append(le(UInt16(1))); d.append(le(UInt16(1)))
    d.append(le(UInt32(sampleRate))); d.append(le(UInt32(sampleRate) * 2)); d.append(le(UInt16(2))); d.append(le(UInt16(16)))
    d.append("data".data(using: .ascii)!); d.append(le(UInt32(pcm.count))); d.append(pcm)
    return d
}

guard CommandLine.arguments.count == 2 else {
    print("usage: swift sons.swift <output folder>")
    exit(1)
}
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for (name, samples) in sounds {
    try wav(samples).write(to: folder.appendingPathComponent(name + ".wav"))
}
print("\(sounds.count) sounds written to \(folder.path)")
