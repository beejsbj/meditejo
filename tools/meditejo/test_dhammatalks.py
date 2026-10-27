"""Offline tests for dhammatalks.py: parsing, the snapshot, and its checks.

    python3 -I -m unittest discover -s tools/meditejo -p 'test_dhammatalks.py'

Nothing here touches the network; the HTML is trimmed from the real pages.
"""

import datetime
import gzip
import json
import tempfile
import unittest
from pathlib import Path

import dhammatalks as d

YEAR_PAGE = """
<nav aria-labelledby="archiveNavHeader" class="sidebar_left scroll-shadow">
  <a class="nav-link" href="/audio/evening/">2026</a>
  <a class="nav-link active" aria-current="page" href="/audio/evening/2025/">2025</a>
  <a class="nav-link" href="/audio/evening/2024/">2024</a>
</nav>
<ul>
<li id="251231-an-auspicious-night" class="list-group-item li-audio transcribed "><button class="play" data-active="false" data-link="/Archive/y2025/251231_An_Auspicious_Night.mp3"><span class="visually-hidden">Play Audio</span></button><span class="smalldate">31</span><a href="/audio/evening/2025/251231-an-auspicious-night.html" class="audio" title="download talk"><span>An Auspicious Night</span></a><a href="/Archive/y2025/251231_An_Auspicious_Night.mp3" class="visually-hidden">Download</a></li>
<li id="251229-again-again" class="list-group-item li-audio "><button class="play" data-link="/Archive/y2025/251229_Again_&_Again.mp3"></button><a href="/audio/evening/2025/251229-again-again.html" class="audio"><span>Again &amp; Again</span></a></li>
<li id="0308n3-anger" class="list-group-item li-audio "><button class="play" data-link="/Archive/y2003/0308n3a1 Anger.mp3"></button><a href="/audio/evening/2003/0308n3-anger.html" class="audio"><span>Anger</span></a></li>
<li id="no-audio" class="list-group-item li-audio "><a href="/audio/evening/2025/no-audio.html" class="audio"><span>No audio here</span></a></li>
</ul>
"""

GUIDED = """
<h1>Guided Meditations</h1>
<p>Guided breath and metta meditations.</p>
<p class="zip"><a href="/x.zip">Full set zip</a></p>
<ul class="list-group list-group-flush">
  <li><a href="/Archive/guided_meditations/01GuidedMetta(4min).mp3" class="audio"><span class="smalldate mono"> 4m</span>Metta</a></li>
  <li><a href="/Archive/guided_meditations/05_Guided_Breath_-_Quick_Version_(12min).mp3" class="audio"><span class="smalldate mono">12m</span>Breath (short version)</a></li>
</ul>
"""

COLLECTIONS = """
<h1>Evening Talks Collected by Theme</h1>
<h2 class="month" id="basics">Basics</h2>
<p>A graduated series of 50 Dhamma talks.</p>
<div class="zip"><a href="/all.zip">Full set zip</a></div>
<ul class="list-group list-group-flush audio-archive">
<li class="list-group-item"><a href="/Archive/basics_collection/01%20Strength%20from%20the%20Basics.mp3" class="audio"><span class="smalldate mono"> 1</span> Strength from the Basics</a></li>
<li class="list-group-item"><a href="/Archive/basics_collection/10%20Pleasure%20&amp;%20Pain.mp3" class="audio"><span class="smalldate mono">10</span> Pleasure &amp; Pain</a></li>
</ul>
<h2 class="month" id="other"><a href="/mp3_topical_index.html">Other Themed Collections.</a></h2>
"""


class ParsingTest(unittest.TestCase):
    def test_year_page_talks_and_sidebar(self):
        items, years = d.parse_year_page(YEAR_PAGE)
        self.assertEqual(
            [i["key"] for i in items],
            ["251231-an-auspicious-night", "251229-again-again", "0308n3-anger"],
            "an entry with no audio file is left out",
        )
        self.assertEqual(items[1]["title"], "Again & Again")
        self.assertEqual(items[1]["audio"], "/Archive/y2025/251229_Again_&_Again.mp3")
        self.assertEqual(
            years,
            [
                ("2026", "/audio/evening/"),
                ("2025", "/audio/evening/2025/"),
                ("2024", "/audio/evening/2024/"),
            ],
        )

    def test_dates_from_keys(self):
        self.assertEqual(d.date_of_key("251231-an-auspicious-night"), "2025-12-31")
        self.assertEqual(d.date_of_key("0308n3-anger"), "2003-08")
        self.assertEqual(
            d.date_of_key("odd-key", "/Archive/y2004/odd.mp3"), "2004"
        )
        self.assertEqual(d.date_of_key("odd-key"), "")
        self.assertEqual(d.date_of_key("251301-x"), "", "month 13 is not a date")

    def test_guided_minutes(self):
        guided = d.parse_guided(GUIDED)
        self.assertEqual(guided["description"], "Guided breath and metta meditations.")
        self.assertEqual(
            [(i["title"], d.minutes_to_seconds(i["label"])) for i in guided["items"]],
            [("Metta", 240), ("Breath (short version)", 720)],
        )

    def test_collections_skip_links_without_a_list(self):
        sections = d.parse_collections(COLLECTIONS)
        self.assertEqual([s["id"] for s in sections], ["basics"])
        self.assertEqual(
            sections[0]["description"], "A graduated series of 50 Dhamma talks."
        )
        self.assertEqual(
            [i["title"] for i in sections[0]["items"]],
            ["Strength from the Basics", "Pleasure & Pain"],
        )

    def test_item_keys_are_stable_slugs(self):
        self.assertEqual(
            d.item_key("basics", "/Archive/basics_collection/01%20Strength%20from%20the%20Basics.mp3"),
            "basics-01-strength-from-the-basics",
        )


class SnapshotTest(unittest.TestCase):
    def snapshot(self):
        evening, _ = d.parse_year_page(YEAR_PAGE)
        morning = [
            {
                "key": "261018-the-perfection-of-equanimity",
                "title": "The Perfection of Equanimity",
                "audio": "/Archive/shorttalks/y2026/261018(short)_The_Perfection_of_Equanimity.mp3",
                "page": "/audio/morning/2026/261018-the-perfection-of-equanimity.html",
            }
        ]
        return d.build_snapshot(
            [("e", evening), ("m", morning), ("e", evening)],  # a repeat page
            d.parse_guided(GUIDED),
            d.parse_collections(COLLECTIONS),
            "2026-10-27T12:00:00Z",
        )

    def test_talks_are_newest_first_and_unique(self):
        talks = self.snapshot()["talks"]
        self.assertEqual(
            [(t[0], t[1], t[3]) for t in talks],
            [
                ("m", "261018-the-perfection-of-equanimity", "2026-10-18"),
                ("e", "251231-an-auspicious-night", "2025-12-31"),
                ("e", "251229-again-again", "2025-12-29"),
                ("e", "0308n3-anger", "2003-08"),
            ],
        )

    def test_page_is_stored_only_when_it_is_not_the_usual_one(self):
        for row in self.snapshot()["talks"]:
            self.assertEqual(len(row), 5, row)
        odd = [
            {"key": "251231-x", "title": "X", "audio": "/a.mp3", "page": "/elsewhere.html"}
        ]
        row = d.build_snapshot([("e", odd)], d.parse_guided(GUIDED), [], "t")["talks"][0]
        self.assertEqual(row[5], "/elsewhere.html")

    def test_courses_carry_group_and_seconds(self):
        courses = {c["id"]: c for c in self.snapshot()["courses"]}
        self.assertEqual(courses["guided"]["group"], "practice")
        self.assertEqual(courses["guided"]["items"][0][3], 240)
        self.assertEqual(courses["basics"]["group"], "talks")
        self.assertEqual(courses["basics"]["anchor"], "basics")

    def test_encoding_is_deterministic(self):
        a, _ = d.encode(self.snapshot())
        b, _ = d.encode(self.snapshot())
        self.assertEqual(a, b)


class CheckTest(unittest.TestCase):
    def write(self, snapshot):
        tmp = Path(tempfile.mkdtemp())
        gz, raw = d.encode(snapshot)
        (tmp / d.ASSET).write_bytes(gz)
        (tmp / d.MANIFEST).write_text(json.dumps(d.manifest_for(snapshot, gz, raw)))
        return tmp

    def snapshot(self, as_of="2026-10-27T12:00:00Z"):
        evening, _ = d.parse_year_page(YEAR_PAGE)
        return d.build_snapshot(
            [("e", evening)], d.parse_guided(GUIDED), [], as_of
        )

    def test_a_good_snapshot_passes(self):
        self.assertEqual(d.check(self.write(self.snapshot()), None), [])

    def test_a_tampered_asset_is_caught(self):
        out = self.write(self.snapshot())
        gz = (out / d.ASSET).read_bytes()
        (out / d.ASSET).write_bytes(gzip.compress(gzip.decompress(gz) + b" "))
        self.assertTrue(any("SHA-256" in p for p in d.check(out, None)))

    def test_age_limit(self):
        out = self.write(self.snapshot("2026-01-01T00:00:00Z"))
        now = datetime.datetime(2026, 3, 1, tzinfo=datetime.timezone.utc)
        self.assertEqual(d.check(out, 90, now), [])
        problems = d.check(out, 45, now)
        self.assertEqual(len(problems), 1)
        self.assertIn("59 days old", problems[0])
        self.assertIn("dhammatalks.py build", problems[0])


if __name__ == "__main__":
    unittest.main()
