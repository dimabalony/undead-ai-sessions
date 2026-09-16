# Renders the labels the demo GIF overlays (docs/demo/demo.filter): two corner tags, a title card, a closing caption.
from PIL import Image, ImageDraw, ImageFont
import os
W, H = 1000, 531
def font(size):
    for f in ("/System/Library/Fonts/Menlo.ttc", "/System/Library/Fonts/SFNSMono.ttf", "/Library/Fonts/SF-Compact.ttf",
              "/Library/Fonts/Arial Unicode.ttf"):
        if os.path.exists(f):
            try: return ImageFont.truetype(f, size, index=1 if f.endswith("Menlo.ttc") else 0)  # Menlo Bold
            except Exception: return ImageFont.truetype(f, size)
    return ImageFont.load_default()
out = os.path.dirname(os.path.abspath(__file__))
def pill(name, text, bg):
    f = font(22); pad = 14
    tw = int(f.getlength(text)); w, h = tw + 2 * pad, 42
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=10, fill=bg)
    d.text((pad, (h - 22) // 2 - 3), text, font=f, fill=(255, 255, 255, 255))
    im.save(os.path.join(out, name))
pill("label-without.png", "without undead", (150, 40, 40, 235))
pill("label-with.png", "with undead", (32, 120, 70, 235))
pill("caption-end.png", "Same tab. Same conversation. Nothing typed.", (32, 120, 70, 235))
card = Image.new("RGB", (W, H), (18, 18, 18)); d = ImageDraw.Draw(card)
lines = [("Gone.", font(64), (255, 255, 255)), ("Every quit, every reboot, every macOS update.", font(28), (170, 170, 170)),
         ("Now the same thing with undead:", font(28), (90, 200, 130))]
y = 150
for text, f, color in lines:
    d.text(((W - f.getlength(text)) / 2, y), text, font=f, fill=color); y += 82 if f.size == 64 else 52
card.save(os.path.join(out, "card.png"))
print("labels written")
