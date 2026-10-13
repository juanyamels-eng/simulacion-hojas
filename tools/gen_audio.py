#!/usr/bin/env python3
"""Genera todos los sonidos y la música de Villa Hojarasca (100 % originales, sintetizados).

Técnicas: ruido filtrado por FFT (bucles perfectos), síntesis aditiva tipo piano/guitarra,
campanas inarmónicas, barridos FM para pájaros y reverberación por convolución.
Uso: python3 tools/gen_audio.py  ->  assets/audio/*.wav (22,05 kHz, mono, 16 bits)
"""
import os
import wave
import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(20241013)


def t(sec):
    return np.arange(int(sec * SR)) / SR


def noise(sec):
    return rng.standard_normal(int(sec * SR))


def band(x, lo, hi, soft=0.15):
    """Filtro paso banda por FFT (circular: perfecto para bucles)."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    lo_m = 1 / (1 + np.exp(-(f - lo) / max(lo * soft, 1)))
    hi_m = 1 / (1 + np.exp((f - hi) / max(hi * soft, 1)))
    return np.fft.irfft(spec * lo_m * hi_m, len(x))


def env(n, a=0.005, d=0.2, curve=4.0):
    tt = np.arange(n) / SR
    e = np.minimum(tt / max(a, 1e-4), 1.0) * np.exp(-np.maximum(tt - a, 0) * curve / max(d, 1e-4))
    return e


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def reverb(x, sec=1.6, mix=0.25, damp=3.5):
    ir_n = int(sec * SR)
    ir = rng.standard_normal(ir_n) * np.exp(-np.arange(ir_n) / SR * damp)
    ir = band(ir, 200, 6000)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    n = len(x) + ir_n
    wet = np.fft.irfft(np.fft.rfft(x, n) * np.fft.rfft(ir, n), n)[: len(x)]
    return x * (1 - mix) + norm(wet, np.max(np.abs(x))) * mix


def fade(x, fi=0.005, fo=0.02):
    n = len(x)
    a = int(fi * SR)
    b = int(fo * SR)
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)
    if b > 0:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def save(name, x, peak=0.85):
    x = norm(np.asarray(x, dtype=np.float64), peak)
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def crackle(sec, density=120, lo=1500, hi=7000):
    n = int(sec * SR)
    x = np.zeros(n)
    idx = rng.integers(0, n, int(density * sec))
    x[idx] = rng.standard_normal(len(idx)) * rng.uniform(0.3, 1.0, len(idx))
    return band(x, lo, hi)


def leaf_crunch(sec, bright=1.0, dens=200):
    body = band(noise(sec), 700 * bright, 5000 * bright) * 0.5
    cr = crackle(sec, dens, 1800 * bright, 8000)
    return (body + cr * 2.5) * env(int(sec * SR), 0.01, sec * 0.5, 3.0)


def bell(freq, sec, partials=((1, 1.0), (2.76, 0.4), (5.4, 0.2), (8.93, 0.08)), decay=3.0):
    tt = t(sec)
    x = np.zeros_like(tt)
    for k, (ratio, amp) in enumerate(partials):
        x += amp * np.sin(2 * np.pi * freq * ratio * tt) * np.exp(-tt * decay * (1 + k * 0.7))
    return x * np.minimum(tt / 0.003, 1)


def piano(freq, sec, vel=1.0):
    tt = t(sec)
    x = np.zeros_like(tt)
    for h in range(1, 9):
        inh = h * np.sqrt(1 + 0.0004 * h * h)
        amp = vel / (h ** 1.4) * (1.0 if h < 4 else 0.6)
        x += amp * np.sin(2 * np.pi * freq * inh * tt + rng.uniform(0, 6)) * np.exp(-tt * (0.9 + h * 0.55))
    hammer = band(noise(0.03), 1000, 5000) * env(int(0.03 * SR), 0.001, 0.01, 6) * 0.05
    x[: len(hammer)] += hammer
    return x * np.minimum(tt / 0.004, 1)


def guitar(freq, sec, vel=1.0):
    tt = t(sec)
    x = np.zeros_like(tt)
    pluck_pos = 0.2
    for h in range(1, 12):
        amp = vel * abs(np.sin(np.pi * h * pluck_pos)) / (h ** 1.1)
        x += amp * np.sin(2 * np.pi * freq * h * tt) * np.exp(-tt * (1.4 + h * 0.9))
    return x * np.minimum(tt / 0.002, 1)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def place(buf, x, at):
    i = int(at * SR)
    j = min(len(buf), i + len(x))
    if i < len(buf):
        buf[i:j] += x[: j - i]


# ----------------------------------------------------------------- efectos

def gen_sfx():
    for k in range(1, 5):
        save("step_leaves_%d" % k, fade(leaf_crunch(0.28, rng.uniform(0.8, 1.15), 260)), 0.8)
    for k in range(1, 4):
        x = band(noise(0.16), 200, 1800) * env(int(0.16 * SR), 0.004, 0.06, 4)
        save("step_grass_%d" % k, fade(x), 0.6)
    for k in range(1, 4):
        save("grab_%d" % k, fade(leaf_crunch(0.35, 1.1, 320)), 0.85)
    for k in range(1, 4):
        x = leaf_crunch(0.6, 0.9, 180) * (1 + 0.5 * np.sin(np.linspace(0, 3, int(0.6 * SR))))
        save("rustle_%d" % k, fade(x), 0.8)
    sw = band(noise(0.3), 600, 3000) * np.sin(np.linspace(0, np.pi, int(0.3 * SR))) ** 2
    save("swish", fade(sw), 0.5)
    # Bolsa: arrugado de plástico + nudo.
    crinkle = crackle(0.7, 500, 2500, 9000) * env(int(0.7 * SR), 0.02, 0.4, 2)
    tie = np.sin(2 * np.pi * np.cumsum(np.linspace(300, 900, int(0.18 * SR))) / SR) * env(int(0.18 * SR), 0.005, 0.1, 5) * 0.3
    bc = np.zeros(int(0.9 * SR))
    place(bc, crinkle, 0)
    place(bc, tie, 0.62)
    save("bag_close", fade(bc), 0.8)
    th = band(noise(0.35), 60, 900) * env(int(0.35 * SR), 0.002, 0.08, 5) + np.sin(2 * np.pi * 70 * t(0.35)) * env(int(0.35 * SR), 0.002, 0.12, 5)
    save("bag_thud", fade(th), 0.9)
    n = int(0.45 * SR)
    sweep = band(noise(0.45), 400, 4000) * np.sin(np.linspace(0, np.pi, n)) ** 1.5
    save("bag_throw", fade(sweep), 0.6)
    dep = np.zeros(int(1.0 * SR))
    place(dep, th, 0.0)
    place(dep, leaf_crunch(0.8, 0.9, 300) * 0.8, 0.05)
    save("bin_deposit", fade(dep), 0.9)
    big = leaf_crunch(1.3, 0.85, 500) + band(noise(1.3), 150, 900) * env(int(1.3 * SR), 0.01, 0.3, 3) * 0.6
    save("pile_jump", fade(reverb(big, 0.6, 0.15)), 0.9)
    save("jump", fade(band(noise(0.25), 300, 1500) * env(int(0.25 * SR), 0.01, 0.1, 4)), 0.4)
    # Puerta: chirrido + pestillo.
    tt = t(0.9)
    f = 420 + 120 * np.sin(2 * np.pi * 3.5 * tt) + 60 * rng.standard_normal(len(tt)).cumsum() / 400
    creak = np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR)) * env(len(tt), 0.05, 0.6, 2.5)
    creak = band(creak, 300, 3000) * 0.5
    gate = np.zeros(int(1.2 * SR))
    place(gate, bell(1800, 0.15, ((1, 1), (2.3, 0.5)), 30) * 0.5, 0.0)
    place(gate, creak, 0.1)
    save("gate_open", fade(gate), 0.7)
    tt = t(1.4)
    hum = np.sin(2 * np.pi * np.cumsum(np.linspace(30, 95, len(tt))) / SR)
    save("duct_on", fade(band(hum + 0.3 * noise(1.4), 40, 2000) * np.minimum(tt / 0.8, 1) * env(len(tt), 0.5, 1.2, 1)), 0.7)
    tt = t(2.5)
    g = band(noise(2.5), 120, 900) * np.sin(np.pi * tt / 2.5) ** 2
    save("gust", fade(g), 0.6)
    # Pájaros: trinos con barridos de frecuencia.
    for k in range(1, 4):
        out = np.zeros(int(1.4 * SR))
        at = 0.0
        for c in range(rng.integers(3, 7)):
            d = rng.uniform(0.05, 0.12)
            tt = t(d)
            f0 = rng.uniform(2500, 4200)
            sweep = f0 + rng.uniform(-1500, 1500) * (tt / d) + 300 * np.sin(2 * np.pi * rng.uniform(20, 45) * tt)
            ch = np.sin(2 * np.pi * np.cumsum(sweep) / SR) * np.sin(np.pi * tt / d) ** 2
            place(out, ch, at)
            at += d + rng.uniform(0.03, 0.12)
        save("bird_%d" % k, fade(reverb(out, 0.8, 0.2)), 0.5)


def loop(sec, x):
    """Asegura un bucle sin clic: el filtrado FFT ya es circular."""
    return x[: int(sec * SR)]


def gen_loops():
    sec = 2.0
    tt = t(sec)
    # Rastrillo: púas que raspan con ritmo + hojarasca.
    tines = crackle(sec, 900, 1500, 7000)
    rhythm = 0.6 + 0.4 * np.sin(2 * np.pi * 2.0 * tt) ** 2
    rake = band(noise(sec), 800, 6000) * 0.25 + tines * 2.0
    save("rake_loop", loop(sec, rake * rhythm), 0.7)
    # Soplador: motor (110 Hz, 220 ciclos exactos) + aire.
    motor = sum(np.sin(2 * np.pi * 110 * h * tt) / h for h in range(1, 8))
    motor *= 1 + 0.05 * np.sin(2 * np.pi * 6 * tt)
    air = band(noise(sec), 500, 7000)
    save("blower_loop", band(motor * 0.25 + air * 1.0, 60, 9000), 0.7)
    motor2 = sum(np.sin(2 * np.pi * 70 * h * tt) / h for h in range(1, 10))
    rumble = band(noise(sec), 40, 300)
    save("industrial_loop", band(motor2 * 0.3 + band(noise(sec), 300, 6000) * 1.2 + rumble * 1.5, 30, 9000), 0.8)
    whine = np.sin(2 * np.pi * 900 * tt) * 0.15 + np.sin(2 * np.pi * 1800 * tt) * 0.05
    suck = band(noise(sec), 1500, 9000)
    save("vacuum_loop", whine + suck + band(noise(sec), 100, 600) * 0.4, 0.65)
    save("duct_loop", band(sum(np.sin(2 * np.pi * 60 * h * tt) / h for h in range(1, 5)) * 0.4 + band(noise(sec), 200, 1500) * 0.5, 40, 3000), 0.6)
    sec = 8.0
    tt = t(sec)
    w = band(noise(sec), 80, 650) * (0.6 + 0.4 * np.sin(2 * np.pi * tt / sec) ** 2) * (0.85 + 0.15 * np.sin(2 * np.pi * 3 * tt / sec))
    save("wind_loop", w, 0.55)
    sub = band(noise(sec), 60, 300) * (0.7 + 0.3 * np.sin(2 * np.pi * 2 * tt / sec)) + band(noise(sec), 900, 2500) * 0.05
    save("suburb_loop", sub, 0.4)


def gen_ui():
    save("ui_click", fade(bell(1400, 0.08, ((1, 1), (2.1, 0.3)), 40) + band(noise(0.08), 2000, 6000) * env(int(0.08 * SR), 0.001, 0.01, 8) * 0.3), 0.5)
    x = np.zeros(int(0.9 * SR))
    place(x, bell(midi(88), 0.8), 0)
    place(x, bell(midi(95), 0.7) * 0.8, 0.09)
    save("ui_cash", fade(reverb(x, 0.6, 0.2)), 0.6)
    save("ui_purchase", fade(reverb(x * 0.9, 0.7, 0.25)), 0.6)
    for name, notes, step in [("ui_reward", [72, 76, 79, 84], 0.09), ("ui_achievement", [79, 83, 86, 91, 95], 0.075), ("ui_restore", [67, 71, 74, 79, 83, 86, 91], 0.11)]:
        x = np.zeros(int((len(notes) * step + 1.4) * SR))
        for k, n in enumerate(notes):
            place(x, bell(midi(n), 1.3) * (0.8 + 0.2 * k / len(notes)), k * step)
        save(name, fade(reverb(x, 1.2, 0.3)), 0.6)
    x = np.zeros(int(1.6 * SR))
    for k in range(12):
        place(x, bell(midi(84 + k * 2), 0.8) * (1 - k / 14), k * 0.05)
    save("ui_collect", fade(reverb(x, 1.4, 0.35)), 0.55)
    x = np.zeros(int(0.4 * SR))
    place(x, guitar(midi(52), 0.2), 0)
    place(x, guitar(midi(48), 0.25), 0.12)
    save("ui_error", fade(x), 0.45)
    x = np.zeros(int(0.6 * SR))
    place(x, bell(midi(81), 0.4), 0)
    place(x, bell(midi(76), 0.5), 0.14)
    save("ui_bag_full", fade(x), 0.5)
    save("ui_tool", fade(band(noise(0.12), 1500, 5000) * env(int(0.12 * SR), 0.002, 0.04, 5) + bell(1000, 0.12, ((1, 1),), 30) * 0.4), 0.45)
    paper = band(noise(0.25), 1500, 7000) * np.sin(np.linspace(0, np.pi, int(0.25 * SR)))
    save("ui_open", fade(paper * 0.6), 0.35)
    save("ui_paper", fade(crackle(0.5, 400, 2000, 8000) * env(int(0.5 * SR), 0.02, 0.3, 2)), 0.45)


# ----------------------------------------------------------------- música

def gen_music_1():
    """Piano suave en Re mayor, 72 ppm: I - vi - IV - V con arpegios y una melodía pentatónica."""
    bpm = 72
    beat = 60 / bpm
    bars = 24
    total = bars * 4 * beat + 4
    out = np.zeros(int(total * SR))
    chords = [[50, 57, 62, 66, 69], [47, 54, 59, 62, 66], [43, 50, 55, 59, 62], [45, 52, 57, 61, 64]]
    penta = [62, 64, 66, 69, 71, 74, 76, 78]
    for bar in range(bars):
        ch = chords[bar % 4]
        at = bar * 4 * beat
        place(out, piano(midi(ch[0] - 12), 3.5, 0.7), at)
        pattern = [1, 2, 3, 4, 3, 2, 3, 4]
        for k, idx in enumerate(pattern):
            place(out, piano(midi(ch[idx]), 2.0, 0.32 + 0.05 * (k == 0)), at + k * beat * 0.5)
        if bar % 2 == 1 or bar >= 8:
            for k in range(rng.integers(1, 4)):
                n = penta[rng.integers(0, len(penta))] + 12
                place(out, piano(midi(n), 2.5, 0.42), at + rng.integers(0, 8) * beat * 0.5)
    out = reverb(out, 2.2, 0.32, 2.5)
    out[-int(4 * SR):] *= np.linspace(1, 0, int(4 * SR))
    save("music_1", out, 0.6)


def gen_music_2():
    """Guitara acústica en Sol mayor, punteo lento: G - Em - C - D."""
    bpm = 66
    beat = 60 / bpm
    bars = 20
    total = bars * 4 * beat + 4
    out = np.zeros(int(total * SR))
    chords = [[43, 50, 55, 59, 62], [40, 47, 52, 55, 59], [48, 52, 55, 60, 64], [50, 54, 57, 62, 66]]
    for bar in range(bars):
        ch = chords[bar % 4]
        at = bar * 4 * beat
        place(out, guitar(midi(ch[0]), 3.0, 0.8), at)
        picks = [2, 3, 4, 3, 1, 3, 4, 3]
        for k, idx in enumerate(picks):
            place(out, guitar(midi(ch[idx]), 1.8, 0.35), at + k * beat * 0.5 + rng.uniform(0, 0.012))
        if bar >= 4 and bar % 4 in (1, 3):
            mel = ch[4] + [0, 2, 4, 7][rng.integers(0, 4)]
            place(out, piano(midi(mel + 12), 2.4, 0.3), at + 2 * beat)
    out = reverb(out, 1.8, 0.28, 2.8)
    out[-int(4 * SR):] *= np.linspace(1, 0, int(4 * SR))
    save("music_2", out, 0.6)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    gen_sfx()
    gen_loops()
    gen_ui()
    gen_music_1()
    gen_music_2()
    print("Audio generado en", os.path.abspath(OUT))
