#!/usr/bin/env python3
"""Build narration-master.wav: voice (concat of clips + silence) mixed with synthesized SFX."""
import os, subprocess, json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VO = f"{ROOT}/voiceover"
FPS = 24
A_START = 0.0
B_START = 590 / FPS
C_START = B_START + 8.0
D_START = C_START + 1664 / FPS
TOTAL = D_START + 110 / FPS

# (clip id, absolute start in seconds)
PLAN = [
    ("A1", A_START + 0.8), ("A2", A_START + 6.6), ("A3", A_START + 13.0), ("A4", A_START + 21.1),
    ("B1", B_START + 0.5), ("B2", B_START + 3.4),
    ("C1", C_START + 0.5), ("C2", C_START + 6.6), ("C3", C_START + 13.2), ("C4", C_START + 19.0),
    ("C5", C_START + 24.2), ("C6", C_START + 28.0), ("C7", C_START + 39.0), ("C8", C_START + 46.0),
    ("C9", C_START + 57.5), ("C10", C_START + 63.0),
    ("D1", D_START + 0.7),
]


def ff(*args):
    subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", *args], check=True)


def dur(path):
    return float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                          "-of", "csv=p=0", path]).decode())


# 1. mp3 -> 48k stereo pcm wav
lens = {}
for cid, _ in PLAN:
    ff("-i", f"{VO}/{cid}.mp3", "-ar", "48000", "-ac", "2", "-c:a", "pcm_s16le", f"{VO}/{cid}.wav")
    lens[cid] = dur(f"{VO}/{cid}.wav")

# 2. timing checks
rows, prev_end, prev_start = [], 0.0, None
for cid, st in PLAN:
    assert st >= prev_end - 1e-6, f"overlap before {cid}: starts {st:.2f}, previous ends {prev_end:.2f}"
    if prev_start is not None:
        assert st - prev_start >= 2.0, f"start gap < 2.0s at {cid}"
    rows.append((cid, st, st + lens[cid]))
    prev_end, prev_start = st + lens[cid], st
assert prev_end <= TOTAL, "narration runs past end of video"
print(f"total video duration {TOTAL:.3f}s; last narration ends {prev_end:.3f}s")

# 3. voice master by concat (clips never overlap)
seg = f"{VO}/concat_segments"
os.makedirs(seg, exist_ok=True)
lines, cursor = [], 0.0
for n, (cid, st) in enumerate(PLAN):
    gap = st - cursor
    if gap > 0.001:
        ff("-f", "lavfi", "-t", f"{gap:.4f}", "-i", "anullsrc=r=48000:cl=stereo", "-c:a", "pcm_s16le", f"{seg}/sil_{n:02d}.wav")
        lines.append(f"file 'sil_{n:02d}.wav'")
    lines.append(f"file '../{cid}.wav'")
    cursor = st + lens[cid]
tail = TOTAL - cursor
ff("-f", "lavfi", "-t", f"{tail:.4f}", "-i", "anullsrc=r=48000:cl=stereo", "-c:a", "pcm_s16le", f"{seg}/sil_tail.wav")
lines.append("file 'sil_tail.wav'")
open(f"{seg}/concat.txt", "w").write("\n".join(lines) + "\n")
ff("-f", "concat", "-safe", "0", "-i", f"{seg}/concat.txt", "-c:a", "pcm_s16le", f"{VO}/voice-master.wav")

# 4. synthesized SFX
sfx = f"{VO}/sfx"
os.makedirs(sfx, exist_ok=True)


def synth(name, expr, d, af=None):
    args = ["-f", "lavfi", "-i", f"aevalsrc={expr}:d={d}:s=48000"]
    if af:
        args += ["-af", af]
    ff(*args, "-ac", "2", "-c:a", "pcm_s16le", f"{sfx}/{name}.wav")


boom = "sin(2*PI*(140*(1-exp(-3*t))/3+35*t))*exp(-2.2*t)+0.5*(random(0)*2-1)*exp(-12*t)"
synth("boom", boom, 1.8)
synth("riser", "sin(2*PI*(150*t+265*t*t))*(t/2.26)*(t/2.26)*0.5+(random(0)*2-1)*(t/2.26)*(t/2.26)*(t/2.26)*0.3", 2.26,
      af="highpass=f=300")
synth("shimmer", "exp(-2*t)*0.1*(sin(2*PI*523.25*t)+sin(2*PI*659.25*t)+sin(2*PI*783.99*t)+sin(2*PI*1046.5*t))", 2.4)
synth("whoosh", "(random(0)*2-1)*sin(PI*t/0.7)*sin(PI*t/0.7)*0.5", 0.7, af="highpass=f=800,lowpass=f=7000")

# (file, absolute start, gain)
SFX = [
    ("boom", B_START + 0.55, 0.55),
    ("riser", B_START + 3.4, 0.45),
    ("boom", B_START + 5.66, 0.8),
    ("shimmer", B_START + 5.66, 0.8),
    ("boom", B_START + 6.36, 0.3),
    ("whoosh", B_START + 7.3, 0.6),
]
inputs, filt = [], []
for n, (f, st, g) in enumerate(SFX):
    inputs += ["-i", f"{sfx}/{f}.wav"]
    ms = int(st * 1000)
    filt.append(f"[{n}:a]volume={g},adelay={ms}|{ms}[s{n}]")
mix = "".join(f"[s{n}]" for n in range(len(SFX)))
filt.append(f"{mix}amix=inputs={len(SFX)}:duration=longest:normalize=0,apad=whole_dur={TOTAL:.3f},atrim=0:{TOTAL:.3f}[sfx]")
ff(*inputs, "-filter_complex", ";".join(filt), "-map", "[sfx]", "-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2", f"{VO}/sfx-master.wav")

# 5. final narration master = voice + sfx
ff("-i", f"{VO}/voice-master.wav", "-i", f"{VO}/sfx-master.wav",
   "-filter_complex", f"[0:a]volume=1.9[v];[1:a]volume=0.8[x];[v][x]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.9:level=disabled,atrim=0:{TOTAL:.3f}[a]",
   "-map", "[a]", "-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2", f"{VO}/narration-master.wav")

# 6. timing plan
with open(f"{ROOT}/copy/timestamps.md", "w") as fh:
    fh.write("# Narration timing plan (absolute seconds in the final video)\n\n")
    fh.write(f"Segments: A logo intro 0.00-{B_START:.2f} | B reveal {B_START:.2f}-{C_START:.2f} | "
             f"C recording {C_START:.2f}-{D_START:.2f} | D outro {D_START:.2f}-{TOTAL:.2f}\n\n")
    fh.write("Mode: no retiming needed. All narration fits inside the video; start gaps are all >= 2.0s.\n\n")
    fh.write("clip | start | end | measured_len\n--- | --- | --- | ---\n")
    for cid, s, e in rows:
        fh.write(f"{cid} | {s:.2f} | {e:.2f} | {lens[cid]:.2f}\n")
print("narration-master.wav built")
