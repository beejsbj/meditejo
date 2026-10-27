"""Write a broad spec set for checking the port while it is built.

    python3 -I tools/meditejo/art/reference/dev_specs.py > /tmp/art-specs.json

Eight seeds of every class in the meaning map, each drawn three ways (the
whole card, the ground alone, the figures on flat paper), still and at a
moving frame. Bells also get frames soon after the strike.
"""
import json
import re
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
compose = (HERE / 'compose.js').read_text()
body = compose[compose.index('const MAP = {'):compose.index('};', compose.index('const MAP = {'))]
classes = re.findall(r"^\s+'?([a-z]+)'?: \{ label:", body, re.M)

specs = []
for cls in classes:
    for i in range(8):
        seed = f'{cls}#{i}'
        base = {'cls': cls, 'seed': seed}
        frames = [('', 60, True), ('@7.3', 7.3, False)]
        if cls.startswith('bell'):
            frames += [('@0.4', 0.4, False), ('@0.9', 0.9, False), ('@2.5', 2.5, False)]
        for only in (None, 'ground', 'figure'):
            for suffix, t, still in frames:
                name = f'{cls}-{i}' + (f'.{only}' if only else '') + suffix
                spec = dict(base, name=name, t=t, still=still)
                if only:
                    spec['only'] = only
                specs.append(spec)
print(json.dumps(specs))
