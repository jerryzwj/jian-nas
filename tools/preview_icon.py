from PIL import Image
import sys

src_path = sys.argv[1]
preview_path = sys.argv[2]
src = Image.open(src_path).convert('RGBA')
print('size', src.size, 'bbox', src.getchannel('A').getbbox())
bg = Image.new('RGBA', src.size, (34, 178, 92, 255))
Image.alpha_composite(bg, src).convert('RGB').resize((512, 512)).save(preview_path)
print('ok')
