# /// script
# requires-python = ">=3.10"
# dependencies = ["cairosvg==2.8.2"]
# ///
"""Regenerate every shipped icon from the frozen house mark.

    uv run tools/meditejo/branding/make_icons.py

1. `dart run tools/meditejo/branding/house_mark.dart` writes
   assets/branding/house_mark.svg (the Tidewater tile and the shelter, 108 ×
   108) and house_mark_glyph.svg from the frozen geometry in
   assets/branding/house_mark.json. (`--freeze SEED` there replaces the
   frozen mark; nothing here does.)
2. This script turns the SVG into:
   - Android's adaptive icon: a solid background, a vector foreground and a
     one-colour monochrome layer (Android 13+ themed icons);
   - the legacy mipmaps (48–192 px), the notification and widget glyphs;
   - the iOS AppIcon set and Icon Composer bundle, and the widget logo;
   - the app's own copies (assets/images/ic_logo.svg and
     assets/images/app_icons/meditejo.png).
   Square icons (iOS, legacy mipmaps, the app's copy) use house_mark_square.svg,
   where the whole canvas is visible; the adaptive layers keep the mark inside
   Android's 66 dp safe circle.

The SVG keeps to SVG's and Android vector drawables' shared subset (a
background rect, then filled paths, no transforms), so the same path data
serves both.
"""
from pathlib import Path
import json
import subprocess
import xml.etree.ElementTree as ET
from xml.sax.saxutils import quoteattr

import cairosvg

ROOT = Path(__file__).resolve().parents[3]
subprocess.run(['dart', 'run', 'tools/meditejo/branding/house_mark.dart'], cwd=ROOT, check=True)

source = ROOT / 'assets/branding/house_mark.svg'
svg = ET.fromstring(source.read_text())
assert svg.get('viewBox') == '0 0 108 108'
shapes = [e for e in svg if isinstance(e.tag, str)]
assert shapes[0].tag.endswith('rect')
background = shapes[0].attrib['fill']
paths = shapes[1:]
assert paths and all(p.tag.endswith('path') and set(p.attrib) <= {'fill', 'd'} for p in paths)
glyph = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108">' + ''.join(
    f'<path fill={quoteattr(p.attrib["fill"])} d={quoteattr(p.attrib["d"])}/>' for p in paths
) + '</svg>\n'
mono = (ROOT / 'assets/branding/house_mark_glyph.svg').read_text()
# Square icons show their whole canvas, so the mark fills more of it.
square = ROOT / 'assets/branding/house_mark_square.svg'
square_paths = [e for e in ET.fromstring(square.read_text()) if isinstance(e.tag, str)][1:]
square_glyph = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108">' + ''.join(
    f'<path fill={quoteattr(p.attrib["fill"])} d={quoteattr(p.attrib["d"])}/>' for p in square_paths
) + '</svg>\n'

# A flavour's own launcher icon would hide this one (the dev flavour once
# carried Medito's artwork).
for flavour in (ROOT / 'android/app/src').iterdir():
    if flavour.name == 'main':
        continue
    stale = list(flavour.glob('res/mipmap*/ic_launcher*'))
    assert not stale, f'{flavour.name} overrides the launcher icon: {stale}'


def write(name, contents):
    target = ROOT / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(contents)


def png(name, size, url=source):
    target = ROOT / name
    target.parent.mkdir(parents=True, exist_ok=True)
    cairosvg.svg2png(url=str(url), write_to=str(target), output_width=size, output_height=size)


def vector(monochrome=False):
    return '<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">\n' + ''.join(
        f'  <path android:fillColor={quoteattr("#FFFFFF" if monochrome else p.attrib["fill"])} android:pathData={quoteattr(p.attrib["d"])}/>\n' for p in paths
    ) + '</vector>\n'


write('assets/images/ic_logo.svg', mono)
# Icon Composer's canvas is 1024pt; give the layer an explicit intrinsic size.
write('ios/Runner/AppIcon.icon/Assets/logo.svg', square_glyph.replace('<svg ', '<svg width="1024" height="1024" ', 1))
write('ios/MeditoWidget/Assets.xcassets/MeditoLogo.imageset/MeditoLogo.svg', square_glyph)
icon = {
    'fill': {'solid': background},
    'groups': [{'layers': [{'image-name': 'logo.svg', 'name': 'Meditejo'}],
                'shadow': {'kind': 'none'}, 'specular': False}],
    'supported-platforms': {'squares': 'shared', 'circles': ['watchOS']},
}
# Icon Composer uses an explicit srgb colour rather than CSS hex.
icon['fill']['solid'] = 'srgb:' + ','.join(f'{int(background[i:i+2], 16) / 255:.5f}' for i in (1, 3, 5)) + ',1.00000'
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
for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    png(res + f'mipmap-{density}/ic_launcher.png', size, square)
png('assets/images/app_icons/meditejo.png', 1024, square)
appicons = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for item in json.loads((appicons / 'Contents.json').read_text())['images']:
    size = round(float(item['size'].split('x')[0]) * float(item['scale'][:-1]))
    png(str((appicons / item['filename']).relative_to(ROOT)), size, square)
print('Regenerated Flutter, Android, iOS app and widget marks from', source.relative_to(ROOT))
