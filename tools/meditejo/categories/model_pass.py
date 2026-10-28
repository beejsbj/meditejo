#!/usr/bin/env python3
"""The model pass over Dharma Seed retreats (categories, second pass).

A model reads every retreat that has talks (name, description, teachers and a
few talk titles) and proposes categories from `assets/categories/categories.json`;
a stronger model audits a sample and the odd cases. The working files live in
`tools/meditejo/categories/pass/` (committed, so a failed run loses nothing);
the result ships as `assets/categories/dharma_seed_pass.json`. See
docs/fork/DECISIONS.md (2026-10-28, categories second pass).

    model_pass.py batches             write the retreat batches to read
    model_pass.py check               validate the proposals (fails until all are in)
    model_pass.py audit-batches       write the batches for the audit
    model_pass.py build               write the shipped asset from both passes
    model_pass.py counts              categories per retreat, before and after

Needs the unpacked snapshot: `catalogue.py fetch`, then this unpacks the
gzip itself. Standard library only.
"""
import argparse
import gzip
import html
import json
import random
import re
import shutil
import sqlite3
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ASSET = ROOT / 'assets/categories/categories.json'
PASS_ASSET = ROOT / 'assets/categories/dharma_seed_pass.json'
SNAPSHOT = ROOT / 'assets/dharma_seed/catalogue.sqlite.gz'
MANIFEST = ROOT / 'assets/dharma_seed/catalogue.json'
WORK = Path(__file__).resolve().parent / 'pass'
INPUT = ROOT / 'build/category-pass/input'
AUDIT_INPUT = ROOT / 'build/category-pass/audit'
BATCH = 100


def open_snapshot():
    tmp = Path(tempfile.mkdtemp(prefix='category-pass-'))
    db = tmp / 'catalogue.sqlite'
    with gzip.open(SNAPSHOT, 'rb') as src, open(db, 'wb') as dst:
        shutil.copyfileobj(src, dst)
    return sqlite3.connect(db), tmp


def plain(text, limit):
    text = html.unescape(re.sub(r'<[^>]+>', ' ', text or ''))
    text = re.sub(r'\s+', ' ', text).strip()
    return text if len(text) <= limit else text[: limit - 1].rstrip() + '…'


def retreats(con):
    rows = con.execute(
        "SELECT id, name, description FROM ds_retreats "
        "WHERE talk_ids != '[]' ORDER BY id"
    ).fetchall()
    out = []
    for rid, name, description in rows:
        teachers = [
            n for (n,) in con.execute(
                'SELECT t.name FROM ds_talks k JOIN ds_teachers t '
                'ON t.id = k.teacher_id WHERE k.retreat_id = ? '
                'GROUP BY t.id ORDER BY COUNT(*) DESC LIMIT 3',
                (rid,),
            )
        ]
        talks = con.execute(
            'SELECT title FROM ds_talks WHERE retreat_id = ? '
            'ORDER BY rec_date, id',
            (rid,),
        ).fetchall()
        titles = [plain(t, 70) for (t,) in talks]
        if len(titles) > 8:
            # Spread the sample over the retreat, not just its first day.
            step = len(titles) / 8
            titles = [titles[int(i * step)] for i in range(8)]
        out.append({
            'id': rid,
            'name': plain(name, 160),
            'teachers': teachers,
            'talks': len(talks),
            'talk_titles': titles,
            'description': plain(description, 600),
        })
    return out


def categories():
    return json.loads(ASSET.read_text(encoding='utf-8'))['categories']


def write_batches(items, folder, size):
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob('batch-*.jsonl'):
        old.unlink()
    for n in range(0, len(items), size):
        path = folder / f'batch-{n // size:03d}.jsonl'
        with open(path, 'w', encoding='utf-8') as f:
            for item in items[n:n + size]:
                f.write(json.dumps(item, ensure_ascii=False) + '\n')
    return (len(items) + size - 1) // size


def read_jsonl(path):
    out = []
    for line in path.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if line:
            out.append(json.loads(line))
    return out


def proposals(folder):
    """Every proposal in [folder], by retreat ID, checked against the list."""
    ids = {c['id'] for c in categories()}
    found = {}
    for path in sorted(folder.glob('batch-*.jsonl')):
        for row in read_jsonl(path):
            rid = int(row['id'])
            cats = row.get('categories')
            if not isinstance(cats, list):
                raise SystemExit(f'{path.name}: {rid} has no categories list')
            unknown = [c for c in cats if c not in ids]
            if unknown:
                raise SystemExit(f'{path.name}: {rid} has unknown {unknown}')
            found[rid] = row
    return found


def cmd_batches(_):
    con, tmp = open_snapshot()
    try:
        items = retreats(con)
    finally:
        con.close()
        shutil.rmtree(tmp)
    n = write_batches(items, INPUT, BATCH)
    print(f'{len(items)} retreats in {n} batches under {INPUT}')


def eligible_ids():
    """The snapshot's retreats with talks: what the pass must cover."""
    con, tmp = open_snapshot()
    try:
        return {
            rid for (rid,) in con.execute(
                "SELECT id FROM ds_retreats WHERE talk_ids != '[]'"
            )
        }
    finally:
        con.close()
        shutil.rmtree(tmp)


def cmd_check(_):
    expected = {}
    for path in sorted(INPUT.glob('batch-*.jsonl')):
        expected[path.name] = [r['id'] for r in read_jsonl(path)]
    inputs = {rid for ids in expected.values() for rid in ids}
    if expected and inputs != eligible_ids():
        raise SystemExit(
            f'The input batches cover {len(inputs)} retreats, not the '
            "snapshot's retreats with talks: run `batches` again"
        )
    done, missing = 0, []
    for name, ids in expected.items():
        out = WORK / 'haiku' / name
        if not out.exists():
            missing.append(name)
            continue
        listed = [int(r['id']) for r in read_jsonl(out)]
        got = set(listed)
        lost = set(ids) - got
        extra = got - set(ids)
        twice = len(listed) - len(got)
        if lost or extra or twice:
            print(f'{name}: missing {sorted(lost)[:10]} extra '
                  f'{sorted(extra)[:10]} repeated {twice}')
        else:
            done += 1
    proposals(WORK / 'haiku')
    print(f'{done}/{len(expected)} batches complete; to do: {" ".join(missing)}')
    if not expected:
        raise SystemExit(f'No batches under {INPUT}: run `batches` first')
    if done != len(expected):
        raise SystemExit(1)


def cmd_audit_batches(args):
    haiku = proposals(WORK / 'haiku')
    con, tmp = open_snapshot()
    try:
        items = {r['id']: r for r in retreats(con)}
    finally:
        con.close()
        shutil.rmtree(tmp)
    odd = sorted(r for r, p in haiku.items() if len(p['categories']) in (0,) or len(p['categories']) >= 4)
    rest = sorted(set(haiku) - set(odd))
    random.seed(args.seed)
    sample = sorted(random.sample(rest, min(args.sample, len(rest))))
    chosen = []
    for rid in odd + sample:
        item = dict(items[rid])
        item['proposed'] = haiku[rid]['categories']
        item['proposed_reason'] = haiku[rid].get('reason', '')
        item['why_audited'] = 'sample' if rid in sample else (
            'none' if not haiku[rid]['categories'] else 'four or more')
        chosen.append(item)
    n = write_batches(chosen, AUDIT_INPUT, args.size)
    print(f'{len(odd)} odd + {len(sample)} sampled = {len(chosen)} in {n} batches')


def final():
    """Haiku's proposals with Sonnet's audit, then the corrections, applied.

    `pass/corrections.jsonl` holds the few readings fixed after review, each
    with its reason; it outranks both models.
    """
    result = {rid: p['categories'] for rid, p in proposals(WORK / 'haiku').items()}
    audited = proposals(WORK / 'sonnet') if (WORK / 'sonnet').exists() else {}
    for rid, row in audited.items():
        result[rid] = row['categories']
    corrections = WORK / 'corrections.jsonl'
    if corrections.exists():
        ids = {c['id'] for c in categories()}
        for row in read_jsonl(corrections):
            rid = int(row['id'])
            if rid not in result or any(c not in ids for c in row['categories']):
                raise SystemExit(f'corrections.jsonl: bad row {row}')
            result[rid] = row['categories']
    return result, audited


def cmd_build(_):
    result, audited = final()
    eligible = eligible_ids()
    if set(result) != eligible:
        raise SystemExit(
            f'The proposals cover {len(set(result) & eligible)} of '
            f'{len(eligible)} retreats with talks '
            f'({len(set(result) - eligible)} unknown): run `check`'
        )
    order = [c['id'] for c in categories()]
    by_category = {c: [] for c in order}
    none = []
    for rid in sorted(result):
        cats = result[rid]
        if not cats:
            none.append(rid)
        for c in cats:
            by_category[c].append(rid)
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    meta = json.loads((WORK / 'meta.json').read_text(encoding='utf-8'))
    lines = [
        '{',
        '  "format": 1,',
        f'  "version": {meta["version"]},',
        f'  "updated": {json.dumps(meta["updated"])},',
        f'  "snapshot": {json.dumps(manifest["asset"]["release"])},',
        f'  "method": {json.dumps(meta["method"], ensure_ascii=False)},',
        f'  "retreats": {len(result)},',
        f'  "none": {json.dumps(none)},',
        '  "categories": {',
    ]
    body = [
        f'    {json.dumps(c)}: {json.dumps(ids)}'
        for c, ids in by_category.items() if ids
    ]
    lines.append(',\n'.join(body))
    lines += ['  }', '}']
    PASS_ASSET.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(f'{len(result)} retreats ({len(audited)} audited), {len(none)} with none '
          f'-> {PASS_ASSET.relative_to(ROOT)} ({PASS_ASSET.stat().st_size} bytes)')


def cmd_counts(_):
    result, audited = final()
    haiku = {rid: p['categories'] for rid, p in proposals(WORK / 'haiku').items()}
    changed = sum(1 for rid in audited if sorted(audited[rid]['categories']) != sorted(haiku[rid]))
    print(f'audited {len(audited)}, changed {changed}')
    for c in categories():
        h = sum(c['id'] in v for v in haiku.values())
        f = sum(c['id'] in v for v in result.values())
        print(f'{c["id"]:16} haiku {h:5}  final {f:5}')


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = parser.add_subparsers(dest='cmd', required=True)
    sub.add_parser('batches').set_defaults(fn=cmd_batches)
    sub.add_parser('check').set_defaults(fn=cmd_check)
    audit = sub.add_parser('audit-batches')
    audit.add_argument('--sample', type=int, default=400)
    audit.add_argument('--size', type=int, default=60)
    audit.add_argument('--seed', type=int, default=586)
    audit.set_defaults(fn=cmd_audit_batches)
    sub.add_parser('build').set_defaults(fn=cmd_build)
    sub.add_parser('counts').set_defaults(fn=cmd_counts)
    args = parser.parse_args()
    args.fn(args)


if __name__ == '__main__':
    sys.exit(main())
