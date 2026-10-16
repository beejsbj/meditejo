# /// script
# requires-python = ">=3.10"
# dependencies = ["cairosvg==2.8.2"]
# ///
"""Run: uv run scripts/regenerate_icons.py

Edit assets/branding/placeholder.svg, then regenerate all shipped marks.
Use a 108x108 SVG with a solid background rect and filled path(s), no transforms.
Keeping paths in SVG/Android's shared subset makes native vector output portable.
"""
from pathlib import Path
import json
import xml.etree.ElementTree as ET
from xml.sax.saxutils import quoteattr

import cairosvg

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / "assets/branding/placeholder.svg"
svg = ET.fromstring(source.read_text())
assert svg.get("viewBox") == "0 0 108 108"
shapes = list(svg)
assert shapes[0].tag.endswith("rect")
background = shapes[0].attrib["fill"]
paths = shapes[1:]
assert paths and all(p.tag.endswith("path") and set(p.attrib) <= {"fill", "d"} for p in paths)
glyph = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108">' + ''.join(
    f'<path fill={quoteattr(p.attrib["fill"])} d={quoteattr(p.attrib["d"])}/>' for p in paths
) + '</svg>\n'

def write(name, contents):
    target = ROOT / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(contents)

def png(name, size):
    target = ROOT / name
    target.parent.mkdir(parents=True, exist_ok=True)
    cairosvg.svg2png(url=str(source), write_to=str(target), output_width=size, output_height=size)

def vector(monochrome=False):
    return '<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">\n' + ''.join(
        f'  <path android:fillColor={quoteattr("#FFFFFF" if monochrome else p.attrib["fill"])} android:pathData={quoteattr(p.attrib["d"])}/>\n' for p in paths
    ) + '</vector>\n'

write('assets/images/ic_logo.svg', glyph)
# Icon Composer's canvas is 1024pt; give the layer an explicit intrinsic size.
write('ios/Runner/AppIcon.icon/Assets/logo.svg', glyph.replace('<svg ', '<svg width="1024" height="1024" ', 1))
write('ios/MeditoWidget/Assets.xcassets/MeditoLogo.imageset/MeditoLogo.svg', glyph)
icon = {
    "fill": {"solid": background},
    "groups": [{"layers": [{"image-name": "logo.svg", "name": "Meditejo"}],
                "shadow": {"kind": "none"}, "specular": False}],
    "supported-platforms": {"squares": "shared", "circles": ["watchOS"]},
}
# Icon Composer uses an explicit srgb colour rather than CSS hex.
icon['fill']['solid'] = 'srgb:' + ','.join(f'{int(background[i:i+2],16)/255:.5f}' for i in (1,3,5)) + ',1.00000'
write('ios/Runner/AppIcon.icon/icon.json', json.dumps(icon, indent=2) + '\n')
res = 'android/app/src/main/res/'
write(res + 'drawable/ic_launcher_background.xml', f'<shape xmlns:android="http://schemas.android.com/apk/res/android"><solid android:color="{background}"/></shape>\n')
write(res + 'drawable/ic_launcher_foreground.xml', vector())
write(res + 'drawable/ic_launcher_monochrome.xml', vector(True))
for name in ['logo', 'widget_logo', 'ic_notification']:
    write(res + f'drawable/{name}.xml', vector(True))
for target in (ROOT / res).glob('drawable*/notification_icon.xml'):
    target.write_text(vector(True))
write(res + 'mipmap-anydpi-v26/ic_launcher.xml', '''<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>
</adaptive-icon>
''')
for density, size in [('mdpi',48), ('hdpi',72), ('xhdpi',96), ('xxhdpi',144), ('xxxhdpi',192)]:
    png(res + f'mipmap-{density}/ic_launcher.png',size)
png('assets/images/app_icons/placeholder.png',1024)
appicons = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for item in json.loads((appicons / 'Contents.json').read_text())['images']:
    size = round(float(item['size'].split('x')[0]) * float(item['scale'][:-1]))
    png(str((appicons / item['filename']).relative_to(ROOT)), size)
print('Regenerated Flutter, Android, iOS app and widget marks from', source.relative_to(ROOT))
