"""Optional developer utility; Python is never needed to run/build the app."""
from pathlib import Path
import json
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
img = Image.new('RGB', (1024, 1024), '#000000')
d = ImageDraw.Draw(img)
d.rounded_rectangle((80, 80, 944, 944), radius=210, fill='#111111')
# A tape, a selected cell and a clear pointer: no external artwork.
for i in range(4):
    x = 150 + i * 187
    d.rounded_rectangle((x, 435, x + 164, 610), radius=25,
                        fill='#FFFFFF' if i == 1 else '#333333',
                        outline='#FFFFFF' if i == 1 else '#777777', width=9)
d.polygon([(350, 328), (478, 328), (414, 411)], fill='#FFFFFF')
d.line([(266, 716), (734, 716)], fill='#FFFFFF', width=29)
d.line([(653, 647), (734, 716), (653, 785)], fill='#FFFFFF', width=29)

def save(path, size):
    img.resize((size, size), Image.Resampling.LANCZOS).save(path)

for folder, size in {'mdpi':48,'hdpi':72,'xhdpi':96,'xxhdpi':144,'xxxhdpi':192}.items():
    save(root / f'android/app/src/main/res/mipmap-{folder}/ic_launcher.png', size)
for p in (root / 'macos/Runner/Assets.xcassets/AppIcon.appiconset').glob('app_icon_*.png'):
    save(p, int(p.stem.split('_')[-1]))
icon_root = root / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for item in json.loads((icon_root / 'Contents.json').read_text())['images']:
    if 'filename' in item:
        size = round(float(item['size'].split('x')[0]) * float(item['scale'].removesuffix('x')))
        save(icon_root / item['filename'], size)
img.save(root / 'windows/runner/resources/app_icon.ico', sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])
