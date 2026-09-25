"""Assemble captured replay frames into a looping GIF (needs Pillow).

    python3 scripts/capture/make_gif.py frames/ docs/assets/replay_iberia.gif
"""
import glob
import sys

from PIL import Image

frames_dir, out = sys.argv[1], sys.argv[2]
frames = [Image.open(f).convert("RGB") for f in sorted(glob.glob(f"{frames_dir}/f_*.png"))]
# One shared palette taken from the final frame, which contains every marker colour
palette = frames[-1].quantize(colors=128, method=Image.Quantize.MEDIANCUT)
q = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in frames]
durations = [120] * (len(q) - 1) + [3500]  # hold the final state
q[0].save(out, save_all=True, append_images=q[1:], duration=durations, loop=0, optimize=True, disposal=1)
print(f"wrote {out} ({len(q)} frames)")
