"""构建资源：生成原创几何便条火星图标；输出固定的不透明 PNG。
输入：下方几何参数；依赖：Pillow（仅资源维护时需要）。
禁止事项：不修改用户资料，不在云端构建中临时安装图像依赖。
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps

root = Path(__file__).resolve().parents[1]
scale = 3
gradient = Image.linear_gradient('L').resize((1024 * scale, 1024 * scale))
image = ImageOps.colorize(gradient, '#153f3d', '#267d6b').convert('RGB')
draw = ImageDraw.Draw(image)

def rect(box, radius, fill):
    draw.rounded_rectangle(tuple(round(x * scale) for x in box), radius=radius * scale, fill=fill)

def polygon(points, fill):
    draw.polygon([(round(x * scale), round(y * scale)) for x, y in points], fill=fill)

rect((190, 232, 812, 728), 144, '#f7f6f2')
polygon([(300, 651), (298, 814), (492, 690)], '#f7f6f2')
rect((306, 374, 642, 416), 21, '#267366')
rect((306, 484, 540, 526), 21, '#267366')
polygon([(780, 124), (806, 208), (890, 234), (806, 260),
         (780, 344), (754, 260), (670, 234), (754, 208)], '#e6a16e')
out = root / '资源/Assets.xcassets/AppIcon.appiconset/AppIcon.png'
out.parent.mkdir(parents=True, exist_ok=True)
image.resize((1024, 1024), Image.Resampling.LANCZOS).save(out)
print(out)
