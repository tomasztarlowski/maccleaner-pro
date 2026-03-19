from PIL import Image, ImageDraw, ImageFilter
import os

out_dir = "icon.iconset"
os.makedirs(out_dir, exist_ok=True)

base = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
d = ImageDraw.Draw(base)

# rounded background
d.rounded_rectangle((80, 80, 944, 944), radius=220, fill=(30, 120, 255, 255))

# soft gradient overlay
overlay = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
do = ImageDraw.Draw(overlay)
do.ellipse((120, 60, 920, 620), fill=(255, 255, 255, 70))
do.ellipse((220, 420, 980, 1080), fill=(140, 60, 255, 90))
overlay = overlay.filter(ImageFilter.GaussianBlur(35))
base = Image.alpha_composite(base, overlay)

d = ImageDraw.Draw(base)

# white broom-like symbol
d.rounded_rectangle((430, 220, 610, 680), radius=40, fill=(255,255,255,240))
d.polygon([(330, 620), (710, 620), (640, 830), (400, 830)], fill=(255,255,255,240))

# sparkle
d.polygon([(760,250),(790,320),(860,350),(790,380),(760,450),(730,380),(660,350),(730,320)], fill=(255,255,255,220))

sizes = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}

for name, s in sizes.items():
    base.resize((s, s), Image.Resampling.LANCZOS).save(os.path.join(out_dir, name))

print("icon.iconset ready")
