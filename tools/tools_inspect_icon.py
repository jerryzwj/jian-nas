from PIL import Image

src = Image.open(r'D:\code\NasCabOS\icon_src.png').convert('RGBA')
print('src size', src.size)
# 统计 alpha 与白色像素
alpha = src.getchannel('A')
bbox = alpha.getbbox()
print('alpha bbox', bbox)
px = src.load()
w, h = src.size
opaque = 0
for y in range(0, h, 4):
    for x in range(0, w, 4):
        if px[x, y][3] > 40:
            opaque += 1
print('opaque sample ratio', round(opaque / ((w // 4) * (h // 4)), 3))

# 合成到绿底预览
bg = Image.new('RGBA', src.size, (22, 163, 74, 255))
preview = Image.alpha_composite(bg, src)
preview.convert('RGB').resize((512, 512)).save(r'D:\code\NasCabOS\icon_preview.png')
print('preview saved')
