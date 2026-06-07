#!/usr/bin/env python3
"""Generate the TimeToGo app icon: a friendly smiling alarm-clock mascot.

Drawn with Pillow at 2x supersampling, then downscaled to 1024x1024 for
crisp anti-aliased edges. Output -> Assets.xcassets/AppIcon.appiconset/icon-1024.png
No external rasterizer needed.
"""
import math
from PIL import Image, ImageDraw, ImageFilter

S = 2                      # supersample factor
W = 1024 * S               # working canvas size
OUT = 1024

def P(v):                  # scale a 1024-space value to working space
    return int(round(v * S))

def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))

# ---------------------------------------------------------------- background
img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
top = (124, 214, 255)      # bright sky cyan
bot = (74, 124, 255)       # friendly periwinkle blue
grad = Image.new("RGBA", (1, W))
gp = grad.load()
for y in range(W):
    t = y / (W - 1)
    gp[0, y] = (*lerp(top, bot, t), 255)
img = grad.resize((W, W))

# soft light bloom from the top-left for depth
bloom = Image.new("RGBA", (W, W), (0, 0, 0, 0))
bd = ImageDraw.Draw(bloom)
bd.ellipse([P(-260), P(-320), P(620), P(420)], fill=(255, 255, 255, 60))
bloom = bloom.filter(ImageFilter.GaussianBlur(P(120)))
img = Image.alpha_composite(img, bloom)

draw = ImageDraw.Draw(img)

cx = 512                   # mascot center (1024-space)
cy = 548
R  = 300                   # clock body radius

# ---------------------------------------------------------------- soft shadow
shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
sd.ellipse([P(cx - 250), P(cy + 250), P(cx + 250), P(cy + 360)], fill=(20, 40, 90, 110))
shadow = shadow.filter(ImageFilter.GaussianBlur(P(34)))
img = Image.alpha_composite(img, shadow)
draw = ImageDraw.Draw(img)

def circle(cx_, cy_, r, fill, outline=None, width=0):
    draw.ellipse([P(cx_ - r), P(cy_ - r), P(cx_ + r), P(cy_ + r)],
                 fill=fill, outline=outline, width=P(width) if width else 0)

# ---------------------------------------------------------------- feet (running)
foot_col = (255, 170, 64)
foot_out = (214, 130, 30)
# back/left foot lifted, right foot planted -> a mid-stride "go!" pose
draw.ellipse([P(cx - 168), P(cy + 232), P(cx - 36), P(cy + 312)], fill=foot_col, outline=foot_out, width=P(7))
draw.ellipse([P(cx + 44),  P(cy + 256), P(cx + 182), P(cy + 332)], fill=foot_col, outline=foot_out, width=P(7))

# ---------------------------------------------------------------- arms
arm_col = (255, 196, 88)
arm_out = (214, 150, 40)
# left arm down-relaxed
draw.line([(P(cx - 250), P(cy + 30)), (P(cx - 322), P(cy + 96))], fill=arm_col, width=P(34))
circle(cx - 330, cy + 104, 26, arm_col, arm_out, 6)
# right arm raised, waving hello
draw.line([(P(cx + 250), P(cy + 10)), (P(cx + 340), P(cy - 86))], fill=arm_col, width=P(34))
circle(cx + 348, cy - 96, 28, arm_col, arm_out, 6)

# ---------------------------------------------------------------- bells on top
bell_col = (255, 206, 86)
bell_out = (214, 150, 40)
for bx in (cx - 158, cx + 158):
    # dome
    draw.pieslice([P(bx - 86), P(cy - R - 96), P(bx + 86), P(cy - R + 74)],
                  start=180, end=360, fill=bell_col, outline=bell_out, width=P(7))
    # little clapper foot
    draw.ellipse([P(bx - 20), P(cy - R - 8), P(bx + 20), P(cy - R + 26)], fill=bell_out)
# hammer between the bells
draw.line([(P(cx), P(cy - R - 70)), (P(cx), P(cy - R - 8))], fill=(120, 80, 30), width=P(16))
circle(cx, cy - R - 78, 26, (90, 110, 130), (60, 75, 95), 5)

# ---------------------------------------------------------------- clock body
circle(cx, cy, R, (255, 200, 92), (214, 150, 40), 0)          # gold rim
circle(cx, cy, R - 30, (255, 249, 232))                        # cream face
# tick marks
for i in range(12):
    a = math.radians(i * 30 - 90)
    r1, r2 = R - 60, R - 40
    x1, y1 = cx + r1 * math.cos(a), cy + r1 * math.sin(a)
    x2, y2 = cx + r2 * math.cos(a), cy + r2 * math.sin(a)
    big = (i % 3 == 0)
    draw.line([(P(x1), P(y1)), (P(x2), P(y2))],
              fill=(214, 150, 40) if big else (236, 196, 120),
              width=P(12 if big else 7))

# ---------------------------------------------------------------- face
navy = (52, 58, 92)
# eyes
for ex in (cx - 92, cx + 92):
    draw.ellipse([P(ex - 40), P(cy - 96), P(ex + 40), P(cy + 4)], fill=navy)
    draw.ellipse([P(ex - 4), P(cy - 78), P(ex + 26), P(cy - 48)], fill=(255, 255, 255))  # highlight
# eyebrows (cheerful raised)
for sgn in (-1, 1):
    ex = cx + sgn * 92
    draw.arc([P(ex - 48), P(cy - 150), P(ex + 48), P(cy - 70)], start=200, end=340, fill=navy, width=P(13))
# cheeks
for chx in (cx - 168, cx + 168):
    draw.ellipse([P(chx - 40), P(cy + 18), P(chx + 40), P(cy + 70)], fill=(255, 142, 168))
# open happy smile
mouth = [P(cx - 104), P(cy + 36), P(cx + 104), P(cy + 168)]
draw.pieslice(mouth, start=0, end=180, fill=navy)
# tongue
draw.pieslice([P(cx - 52), P(cy + 104), P(cx + 52), P(cy + 176)], start=0, end=180, fill=(255, 120, 138))

# ---------------------------------------------------------------- sparkles
def sparkle(sx, sy, s, col=(255, 255, 255, 235)):
    pts = [(sx, sy - s), (sx + s * 0.28, sy - s * 0.28),
           (sx + s, sy), (sx + s * 0.28, sy + s * 0.28),
           (sx, sy + s), (sx - s * 0.28, sy + s * 0.28),
           (sx - s, sy), (sx - s * 0.28, sy - s * 0.28)]
    draw.polygon([(P(x), P(y)) for x, y in pts], fill=col)

sparkle(cx + 300, cy + 150, 34)
sparkle(cx - 300, cy - 150, 24)
sparkle(cx + 250, cy - 240, 18)

# ---------------------------------------------------------------- finish
img = img.convert("RGB").resize((OUT, OUT), Image.LANCZOS)
dest = "TimeToGo/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
img.save(dest, "PNG")
print("wrote", dest)
