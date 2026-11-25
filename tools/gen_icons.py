from PIL import Image, ImageDraw
import os

SRC = r'D:\code\NasCabOS\icon_src2.png'
GREEN = (34, 178, 92, 255)

def load_centered_icon(size_px, padding_ratio):
    """返回 size_px*size_px 的透明画布，白色图标等比居中，四周留 padding_ratio"""
    src = Image.open(SRC).convert('RGBA')
    bbox = src.getchannel('A').getbbox()
    icon = src.crop(bbox)
    inner = int(size_px * (1 - 2 * padding_ratio))
    w, h = icon.size
    scale = inner / max(w, h)
    nw, nh = max(1, int(w * scale)), max(1, int(h * scale))
    icon = icon.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new('RGBA', (size_px, size_px), (0, 0, 0, 0))
    canvas.paste(icon, ((size_px - nw) // 2, (size_px - nh) // 2), icon)
    return canvas

def rounded_square(size_px, radius_ratio=0.22):
    img = Image.new('RGBA', (size_px, size_px), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = int(size_px * radius_ratio)
    d.rounded_rectangle([0, 0, size_px - 1, size_px - 1], radius=r, fill=GREEN)
    return img

def legacy_icon(size_px):
    """绿底圆角方块 + 白色线性图标"""
    base = rounded_square(size_px)
    glyph = load_centered_icon(size_px, 0.16)
    return Image.alpha_composite(base, glyph)

def full_bleed(size_px):
    """满版绿底（maskable 用）+ 图标（更小安全区）"""
    base = Image.new('RGBA', (size_px, size_px), GREEN)
    glyph = load_centered_icon(size_px, 0.24)
    return Image.alpha_composite(base, glyph)

def foreground(size_px):
    return load_centered_icon(size_px, 0.19)

OUT_ANDROID = r'D:\code\NasCabOS\flutter_client\android\app\src\main\res'
DENSITIES = {
    'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0,
}

for d, k in DENSITIES.items():
    launcher = legacy_icon(int(48 * k))
    launcher.save(os.path.join(OUT_ANDROID, f'mipmap-{d}', 'ic_launcher.png'))
    fg = foreground(int(108 * k))
    fg.save(os.path.join(OUT_ANDROID, f'drawable-{d}', 'ic_launcher_foreground.png'))

WEB_ICONS = r'D:\code\NasCabOS\flutter_client\web\icons'
os.makedirs(WEB_ICONS, exist_ok=True)
legacy_icon(192).save(os.path.join(WEB_ICONS, 'Icon-192.png'))
legacy_icon(512).save(os.path.join(WEB_ICONS, 'Icon-512.png'))
if os.path.exists(os.path.join(WEB_ICONS, 'Icon-maskable-192.png')):
    full_bleed(192).save(os.path.join(WEB_ICONS, 'Icon-maskable-192.png'))
if os.path.exists(os.path.join(WEB_ICONS, 'Icon-maskable-512.png')):
    full_bleed(512).save(os.path.join(WEB_ICONS, 'Icon-maskable-512.png'))
legacy_icon(32).save(r'D:\code\NasCabOS\flutter_client\web\favicon.png')

# 交付预览：1024 成品
legacy_icon(1024).convert('RGB').save(r'D:\code\NasCabOS\简NAS-图标-1024.png')
print('icons generated')
