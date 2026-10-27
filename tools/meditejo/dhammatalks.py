#!/usr/bin/env python3 -I
"""Builds the bundled dhammatalks.org catalogue snapshot (metadata only).

    python3 -I tools/meditejo/dhammatalks.py build   [--delay 4] [--out assets/dhammatalks]
    python3 -I tools/meditejo/dhammatalks.py check   [--max-age-days 45]

`build` reads the public listing pages of https://www.dhammatalks.org, and
nothing else:

* the evening talks archive, one page per year (`/audio/evening/`, then each
  year of its sidebar);
* the short morning talks archive, the same way (`/audio/morning/`);
* the guided meditations index (`/mp3_guidedMed_index.html`);
* the talk collections index (`/mp3_collections_index.html`).

It is a polite client: it fetches `/robots.txt` first and refuses any URL it
disallows for our user agent, makes requests one at a time with at least three
seconds between them (`--delay`, default 4), identifies itself, honours
`Retry-After`, and stops on repeated failures. About 47 requests in all.

The output is `catalogue.json.gz` (titles, dates and file addresses; **no
audio**) and `manifest.json` (counts, byte size and SHA-256 of the gzip, and
the date it was read: `asOf`). The app plays each talk from dhammatalks.org
unmodified; the licence is CC BY-NC 4.0 and the app shows it per item.

`check` verifies the committed pair (hash, counts, ordering) and, with
`--max-age-days`, fails when the snapshot is older than the RSS feeds' window
can bridge. The Dart test suite runs the same rule; see
`test/services/dhammatalks/dhammatalks_snapshot_test.dart`.

The snapshot format (schema 1), JSON before gzip::

    {"schema": 1, "asOf": "2026-10-27T11:00:00Z",
     "talks":   [[channel, key, title, "YYYY-MM-DD", audioPath, page?], ...],
     "courses": [{"id", "title", "description", "group", "page", "anchor",
                  "items": [[key, title, audioPath, seconds], ...]}, ...]}

`channel` is `e` (evening) or `m` (morning); `key` is the site's own entry id
(`260131-a-slug`); `page` appears only when it differs from
`/audio/<evening|morning>/<year>/<key>.html`. Talks are newest first.
"""

import argparse
import datetime
import gzip
import hashlib
import html
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import urllib.robotparser
from html.parser import HTMLParser
from pathlib import Path

SITE = "https://www.dhammatalks.org"
USER_AGENT = "Meditejo-catalogue-builder/1.0 (+https://github.com/beejsbj/meditejo)"
SCHEMA = 1
MIN_DELAY = 3.0
DEFAULT_OUT = Path(__file__).resolve().parents[2] / "assets" / "dhammatalks"
ASSET = "catalogue.json.gz"
MANIFEST = "manifest.json"

CHANNELS = {"e": "evening", "m": "morning"}


# --------------------------------------------------------------------- parsing


class _TalkList(HTMLParser):
    """Reads the year pages: `<li class="... li-audio" id=KEY>` entries."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.items = []
        self.years = []  # (label, href) from the sidebar
        self._item = None
        self._in_title = False
        self._in_audio_link = False
        self._side = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        cls = (a.get("class") or "").split()
        if tag == "nav" and "sidebar_left" in cls:
            self._side = True
        if self._side and tag == "a" and "nav-link" in cls:
            self._href = a.get("href")
            self._label = ""
            self._in_year = True
        if tag == "li" and "li-audio" in cls and a.get("id"):
            self._item = {"key": a["id"], "title": "", "audio": None, "page": None}
        elif self._item is not None:
            if tag == "button" and "play" in cls and a.get("data-link"):
                self._item["audio"] = a["data-link"]
            elif tag == "a" and "audio" in cls:
                self._item["page"] = a.get("href")
                self._in_audio_link = True
            elif tag == "span" and self._in_audio_link:
                self._in_title = True
            elif tag == "a" and "visually-hidden" in cls and not self._item["audio"]:
                self._item["audio"] = a.get("href")

    def handle_endtag(self, tag):
        if tag == "nav":
            self._side = False
        if tag == "a" and getattr(self, "_in_year", False):
            self._in_year = False
            self.years.append((self._label.strip(), self._href))
        if tag == "span":
            self._in_title = False
        if tag == "a":
            self._in_audio_link = False
        if tag == "li" and self._item is not None:
            if self._item["audio"] and self._item["title"].strip():
                self._item["title"] = " ".join(self._item["title"].split())
                self.items.append(self._item)
            self._item = None

    def handle_data(self, data):
        if getattr(self, "_in_year", False):
            self._label += data
        if self._item is not None and self._in_title:
            self._item["title"] += data


def parse_year_page(text):
    """(talks, years) from one archive page; talks are dicts, in page order."""
    parser = _TalkList()
    parser.feed(text)
    return parser.items, parser.years


def date_of_key(key, audio=""):
    """The talk's date as `YYYY-MM-DD`, or a shorter prefix when the archive
    names it less exactly.

    The archive names a talk `260131-a-slug` (2026-01-31). Its early retreat
    sittings are `0308n3-a-slug` (August 2003, night 3), which gives a month,
    and anything else falls back to the year in the file's folder (`/y2003/`).
    """
    m = re.match(r"^(\d{2})(\d{2})(\d{2})(?=$|[-_(])", key)
    if m:
        yy, mm, dd = (int(g) for g in m.groups())
        try:
            return datetime.date(2000 + yy, mm, dd).isoformat()
        except ValueError:
            pass
    m = re.match(r"^(\d{2})(\d{2})n\d", key)
    if m and 1 <= int(m.group(2)) <= 12:
        return f"20{m.group(1)}-{m.group(2)}"
    m = re.search(r"/y(\d{4})/", audio)
    return m.group(1) if m else ""


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


class _Collections(HTMLParser):
    """Reads an index of `<ul>` lists under optional `<h2 class=month id=…>`."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.sections = []  # {"id", "title", "description", "items": []}
        self._h2 = None
        self._p = None
        self._link = None
        self._in_minutes = False
        self._in_ul = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        cls = (a.get("class") or "").split()
        if tag == "h2" and "month" in cls:
            self._h2 = {"id": a.get("id", ""), "title": ""}
        elif tag == "p" and self.sections and not self._in_ul:
            self._p = ""
        elif tag == "ul" and "list-group" in cls:
            self._in_ul = True
        elif tag == "a" and self._in_ul and "audio" in cls:
            self._link = {"audio": a.get("href"), "title": "", "label": ""}
        elif tag == "span" and self._link is not None and "smalldate" in cls:
            self._in_minutes = True

    def handle_endtag(self, tag):
        if tag == "h2" and self._h2 is not None:
            title = " ".join(self._h2["title"].split())
            self.sections.append(
                {"id": self._h2["id"], "title": title, "description": "", "items": []}
            )
            self._h2 = None
        elif tag == "p" and self._p is not None:
            if self.sections and not self.sections[-1]["description"]:
                self.sections[-1]["description"] = " ".join(self._p.split())
            self._p = None
        elif tag == "span":
            self._in_minutes = False
        elif tag == "a" and self._link is not None:
            if self.sections and self._link["audio"]:
                self.sections[-1]["items"].append(
                    {
                        "audio": self._link["audio"],
                        "title": " ".join(self._link["title"].split()),
                        "label": self._link["label"].strip(),
                    }
                )
            self._link = None
        elif tag == "ul":
            self._in_ul = False

    def handle_data(self, data):
        if self._h2 is not None:
            self._h2["title"] += data
        elif self._p is not None:
            self._p += data
        elif self._link is not None:
            if self._in_minutes:
                self._link["label"] += data
            else:
                self._link["title"] += data


def parse_collections(text):
    parser = _Collections()
    parser.feed(text)
    return [s for s in parser.sections if s["items"]]


def parse_guided(text):
    """The guided meditations index has one list and no `<h2>`."""
    parser = _Collections()
    parser.sections.append(
        {"id": "guided", "title": "Guided meditations", "description": "", "items": []}
    )
    parser.feed(text)
    section = parser.sections[0]
    m = re.search(r"<h1>.*?</h1>\s*<p>(.*?)</p>", text, re.S)
    if m:
        section["description"] = html.unescape(re.sub(r"<[^>]+>", "", m.group(1))).strip()
    return section


def minutes_to_seconds(label):
    m = re.match(r"^\s*(\d+)\s*m\s*$", label or "")
    return int(m.group(1)) * 60 if m else 0


def item_key(course, audio):
    base = urllib.parse.unquote(audio.rsplit("/", 1)[-1])
    base = re.sub(r"\.mp3$", "", base, flags=re.I)
    return f"{course}-{slug(base)}"


# -------------------------------------------------------------------- snapshot


def derived_page(channel, key):
    return f"/audio/{CHANNELS[channel]}/20{key[:2]}/{key}.html"


def talk_row(channel, item):
    key = item["key"]
    row = [channel, key, item["title"], date_of_key(key, item["audio"]), item["audio"]]
    if item["page"] and item["page"] != derived_page(channel, key):
        row.append(item["page"])
    return row


def build_snapshot(talk_pages, guided, collections, as_of):
    """Assemble the snapshot dict from parsed pages (pure; tested offline)."""
    talks = []
    seen = set()
    for channel, items in talk_pages:
        for item in items:
            marker = (channel, item["key"])
            if marker in seen:
                continue
            seen.add(marker)
            talks.append(talk_row(channel, item))
    talks.sort(key=lambda r: (r[3], r[1], r[0]), reverse=True)

    courses = []
    guided_items = [
        [
            item_key("guided", i["audio"]),
            i["title"],
            i["audio"],
            minutes_to_seconds(i["label"]),
        ]
        for i in guided["items"]
    ]
    courses.append(
        {
            "id": "guided",
            "title": "Guided meditations",
            "description": guided["description"],
            "group": "practice",
            "page": "/mp3_guidedMed_index.html",
            "anchor": "",
            "items": guided_items,
        }
    )
    for section in collections:
        courses.append(
            {
                "id": section["id"],
                "title": section["title"],
                "description": section["description"],
                "group": "talks",
                "page": "/mp3_collections_index.html",
                "anchor": section["id"],
                "items": [
                    [
                        item_key(section["id"], i["audio"]),
                        i["title"],
                        i["audio"],
                        0,
                    ]
                    for i in section["items"]
                ],
            }
        )
    return {"schema": SCHEMA, "asOf": as_of, "talks": talks, "courses": courses}


def ids_in_use(snapshot):
    """The identities a user's library, stats or downloads can hold.

    A talk is `(channel, key)`. A collection is its id. A collection file is
    its key, unless the archive holds the same file, when the app uses the
    archive talk instead (so the collection key is no longer an ID).
    """
    talks = {t[4].lower() for t in snapshot["talks"]}
    ids = {("talk", t[0], t[1]) for t in snapshot["talks"]}
    for course in snapshot["courses"]:
        ids.add(("course", course["id"]))
        for item in course["items"]:
            if item[2].lower() not in talks:
                ids.add(("file", item[0]))
    return ids


def vanished_ids(old, new):
    """Identities in [old] that [new] no longer has, sorted for display."""
    return sorted(ids_in_use(old) - ids_in_use(new))


def encode(snapshot):
    raw = json.dumps(snapshot, ensure_ascii=False, separators=(",", ":")).encode()
    # mtime 0 and a fixed level: the same snapshot always gzips to the same bytes.
    return gzip.compress(raw, compresslevel=9, mtime=0), raw


def manifest_for(snapshot, gz, raw):
    talks = snapshot["talks"]
    return {
        "schema": SCHEMA,
        "asOf": snapshot["asOf"],
        "newest": talks[0][3] if talks else "",
        "oldest": talks[-1][3] if talks else "",
        "counts": {
            "talks": len(talks),
            "evening": sum(1 for t in talks if t[0] == "e"),
            "morning": sum(1 for t in talks if t[0] == "m"),
            "courses": len(snapshot["courses"]),
            "courseItems": sum(len(c["items"]) for c in snapshot["courses"]),
        },
        "bytes": len(raw),
        "asset": {
            "name": ASSET,
            "bytes": len(gz),
            "sha256": hashlib.sha256(gz).hexdigest(),
        },
        "source": SITE,
        "licence": "CC BY-NC 4.0",
    }


# ---------------------------------------------------------------------- client


class Polite:
    """Serial, rate-limited, robots-aware fetching."""

    def __init__(self, delay):
        self.delay = max(delay, MIN_DELAY)
        self._last = 0.0
        self.requests = 0
        self.robots = urllib.robotparser.RobotFileParser()
        self.robots.parse(self._fetch(f"{SITE}/robots.txt").splitlines())

    def _fetch(self, url):
        wait = self._last + self.delay - time.monotonic()
        if wait > 0:
            time.sleep(wait)
        failures = 0
        while True:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            self._last = time.monotonic()
            self.requests += 1
            try:
                with urllib.request.urlopen(req, timeout=30) as response:
                    return response.read().decode("utf-8", "replace")
            except urllib.error.HTTPError as e:
                failures += 1
                if failures >= 3 or e.code not in (429, 500, 502, 503, 504):
                    raise
                retry = e.headers.get("Retry-After", "")
                time.sleep(max(int(retry) if retry.isdigit() else 0, 30 * failures))
            except urllib.error.URLError:
                failures += 1
                if failures >= 3:
                    raise
                time.sleep(30 * failures)

    def get(self, path):
        url = path if path.startswith("http") else SITE + path
        if not self.robots.can_fetch(USER_AGENT, url):
            raise SystemExit(f"robots.txt disallows {url}; not fetching it")
        print(f"  GET {url}", file=sys.stderr)
        return self._fetch(url)


def read_archive(polite, channel):
    """Every year of one archive: landing page (the newest year) plus sidebar."""
    landing = f"/audio/{channel}/"
    items, years = parse_year_page(polite.get(landing))
    pages = [items]
    wanted = []
    for label, href in years:
        if not re.fullmatch(r"\d{4}", label or ""):
            continue
        if href.rstrip("/") == landing.rstrip("/"):
            continue  # the landing page is that year
        wanted.append(href)
    for href in wanted:
        year_items, _ = parse_year_page(polite.get(href))
        pages.append(year_items)
    return [item for page in pages for item in page]


def build(out, delay, allow_id_loss=False):
    polite = Polite(delay)
    evening = read_archive(polite, "evening")
    morning = read_archive(polite, "morning")
    guided = parse_guided(polite.get("/mp3_guidedMed_index.html"))
    collections = parse_collections(polite.get("/mp3_collections_index.html"))
    as_of = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    snapshot = build_snapshot(
        [("e", evening), ("m", morning)], guided, collections, as_of
    )
    gz, raw = encode(snapshot)
    manifest = manifest_for(snapshot, gz, raw)
    previous = out / ASSET
    if previous.exists():
        lost = vanished_ids(json.loads(gzip.decompress(previous.read_bytes())), snapshot)
        if lost and not allow_id_loss:
            for kind, *rest in lost[:20]:
                print(f"  gone: {kind} {' '.join(rest)}", file=sys.stderr)
            raise SystemExit(
                f"{len(lost)} ID(s) in the committed snapshot are not in the new one. "
                "IDs are stored in users' libraries, stats and downloads, so the "
                "app would lose them. If the site really removed or renamed them, "
                "rerun with --allow-id-loss and say so in DECISIONS.md."
            )
    out.mkdir(parents=True, exist_ok=True)
    (out / ASSET).write_bytes(gz)
    (out / MANIFEST).write_text(json.dumps(manifest, indent=2) + "\n")
    print(
        f"{polite.requests} requests; {manifest['counts']['talks']} talks, "
        f"{manifest['counts']['courses']} courses, {len(gz)} bytes gzipped "
        f"({len(raw)} raw); newest {manifest['newest']}",
        file=sys.stderr,
    )
    return manifest


# ----------------------------------------------------------------------- check


def check(out, max_age_days, now=None):
    """Problems with the committed snapshot, as a list of sentences."""
    problems = []
    manifest = json.loads((out / MANIFEST).read_text())
    gz = (out / ASSET).read_bytes()
    if hashlib.sha256(gz).hexdigest() != manifest["asset"]["sha256"]:
        problems.append("the snapshot's SHA-256 differs from manifest.json")
    if len(gz) != manifest["asset"]["bytes"]:
        problems.append("the snapshot's size differs from manifest.json")
    snapshot = json.loads(gzip.decompress(gz))
    if snapshot.get("schema") != SCHEMA:
        problems.append(f"schema {snapshot.get('schema')} is not {SCHEMA}")
    if len(snapshot["talks"]) != manifest["counts"]["talks"]:
        problems.append("the talk count differs from manifest.json")
    if snapshot["asOf"] != manifest["asOf"]:
        problems.append("asOf differs from manifest.json")
    dates = [t[3] for t in snapshot["talks"]]
    if dates != sorted(dates, reverse=True):
        problems.append("talks are not newest first")
    if max_age_days is not None:
        now = now or datetime.datetime.now(datetime.timezone.utc)
        as_of = datetime.datetime.fromisoformat(manifest["asOf"].replace("Z", "+00:00"))
        age = (now - as_of).days
        if age > max_age_days:
            problems.append(
                f"the snapshot is {age} days old (limit {max_age_days}); the RSS "
                "feeds no longer reach back to it. Refresh: "
                "python3 -I tools/meditejo/dhammatalks.py build"
            )
    return problems


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    b = sub.add_parser("build", help="read dhammatalks.org and write the snapshot")
    b.add_argument("--delay", type=float, default=4.0, help="seconds between requests (min 3)")
    b.add_argument("--out", type=Path, default=DEFAULT_OUT)
    b.add_argument(
        "--allow-id-loss",
        action="store_true",
        help="write the snapshot even though IDs of the committed one are gone",
    )
    c = sub.add_parser("check", help="verify the committed snapshot")
    c.add_argument("--max-age-days", type=int, default=None)
    c.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args(argv)
    if args.command == "build":
        build(args.out, args.delay, args.allow_id_loss)
        return 0
    problems = check(args.out, args.max_age_days)
    for problem in problems:
        print(f"dhammatalks snapshot: {problem}", file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
