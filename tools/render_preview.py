"""Offline port of EngineDSP (EngineSynth.swift) to preview sounds and plot their response.
Usage: python3 tools/render_preview.py  -> writes docs/previews/*.wav and response.png"""
import math, wave, numpy as np, os
SR = 22050
TWO_PI = 2 * math.pi
OUT = os.path.join(os.path.dirname(__file__), "..", "docs", "previews")

def throttle_curve(n):
    # idle 1s, ramp up 4s, hold 2s, ramp down 3s, idle 1s
    seg = [(1, 0, 0), (4, 0, 1), (2, 1, 1), (3, 1, 0), (1, 0, 0)]
    return np.concatenate([np.linspace(a, b, int(s * SR), endpoint=False) for s, a, b in seg])

def render(profile, target):
    t = vol = 0.0; tc = 1 - math.exp(-1 / (SR * 0.12)); vc = 1 - math.exp(-1 / (SR * 0.05))
    p1 = p2 = vib = bub = cyc = lp = 0.0
    rng = np.random.default_rng(1)
    out = np.zeros(len(target)); freq = np.zeros(len(target)); tt = np.zeros(len(target))
    for i, tg in enumerate(target):
        t += (tg - t) * tc; vol += (0.8 - vol) * vc
        if profile == "jetson":
            base = 260 * 2 ** (t * 2)
            vib = (vib + TWO_PI * (5.5 + 4 * t) / SR) % TWO_PI
            f = base * (1 + (0.02 + 0.035 * t) * math.sin(vib))
            p1 = (p1 + TWO_PI * f / SR) % TWO_PI; p2 = (p2 + TWO_PI * f * 1.503 / SR) % TWO_PI
            tone = math.sin(p1) + 0.35 * math.sin(2 * p1) + 0.12 * math.sin(3 * p1)
            bub = (bub + TWO_PI * (12 + 22 * t) / SR) % TWO_PI
            s = (tone + 0.22 * math.sin(p2)) * (0.78 + 0.22 * math.sin(bub)) * (0.2 + 0.8 * t) * 0.38
            freq[i] = base
        elif profile == "v8":
            fire = 38 + 170 * t
            cyc = (cyc + fire / SR) % 2
            ph = cyc % 1
            raw = (math.exp(-ph * 7) - 0.14) * (1 if cyc < 1 else 0.72) + rng.uniform(-1, 1) * (0.08 + 0.25 * t)
            lp += (raw - lp) * (1 - math.exp(-TWO_PI * (350 + 3200 * t) / SR))
            s = lp * (0.3 + 0.7 * t) * 0.9
            freq[i] = fire
        else:
            f = 160 * 2 ** (t * 3)
            p1 = (p1 + TWO_PI * f / SR) % TWO_PI; p2 = (p2 + TWO_PI * f * 3.02 / SR) % TWO_PI
            s = (math.sin(p1) + 0.18 * math.sin(p2) + 0.04 * rng.uniform(-1, 1)) * (0.12 + 0.88 * t) * 0.4
            freq[i] = f
        out[i] = math.tanh(s * vol * 1.2); tt[i] = t
    return out, freq, tt

def write_wav(path, x):
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())

if __name__ == "__main__":
    import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
    target = throttle_curve(SR)
    fig, axes = plt.subplots(2, 1, figsize=(9, 6), sharex=True)
    for name, label in [("jetson", "Space Car (default)"), ("v8", "V8 (firing Hz)"), ("electric", "Electric")]:
        x, f, tt = render(name, target)
        write_wav(os.path.join(OUT, f"{name}.wav"), x)
        sec = np.arange(len(x)) / SR
        w = SR // 20  # 50 ms RMS windows
        rms = np.sqrt(np.convolve(x ** 2, np.ones(w) / w, "same"))
        axes[0].plot(sec[::100], f[::100], label=label)
        axes[1].plot(sec[::100], 20 * np.log10(rms[::100] + 1e-4), label=label)
        print(f"{name:9s} pitch {f.min():6.0f}→{f.max():6.0f} Hz  RMS idle {rms[SR//2]:.3f}  full {rms[6*SR]:.3f}  peak {abs(x).max():.2f}")
    axes[0].plot([], []); axes[0].set_ylabel("Pitch (Hz)"); axes[0].legend(); axes[0].set_title("Synth response to throttle sweep (0→100%→0)")
    ax2 = axes[0].twinx(); ax2.plot(np.arange(len(target)) / SR, target * 100, "k:", alpha=.4); ax2.set_ylabel("Throttle % (dotted)")
    axes[1].set_ylabel("Loudness (dBFS)"); axes[1].set_xlabel("Seconds")
    fig.tight_layout(); fig.savefig(os.path.join(OUT, "response.png"), dpi=110)
