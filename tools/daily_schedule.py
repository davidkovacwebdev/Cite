#!/usr/bin/env python3
"""Fill the Daily Challenge schedule ahead.

The game downloads the schedule (daily/schedule.json on the repo's
daily-data branch, see ui/daily/daily_state.gd) and plays the ids listed for
today's UTC date, so every version of the game gets the same Daily. This
script is run by .github/workflows/daily-schedule.yml a few times a day; it
only adds dates that are missing, so a published day never changes unless
it's rerolled on purpose (--reroll DATE).

Each day lists IDS_PER_DAY Wikipedia page ids: the game plays the first 5
whose intro loads and is long enough, the rest are spares. Ids come from the
official playlists (assets/data/multiplayer_playlists/*.json) and don't
repeat within NO_REPEAT_DAYS.

Usage:
  python3 tools/daily_schedule.py --schedule path/to/schedule.json [--days-ahead 7] [--reroll 2026-11-03]
"""

import argparse
import datetime
import json
import pathlib
import random
import re
import sys
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
PLAYLISTS = ROOT / "assets" / "data" / "multiplayer_playlists"
IDS_PER_DAY = 8  # 5 played + 3 spares
NO_REPEAT_DAYS = 365
MIN_SENTENCES = 5  # the game needs 4+ after its own sentence split; ask a bit more
API = "https://en.wikipedia.org/w/api.php"
USER_AGENT = "CiteDailySchedule/1.0 (https://github.com/davidkovacwebdev/Cite)"


def official_ids():
    ids = set()
    for path in sorted(PLAYLISTS.glob("*.json")):
        with open(path, encoding="utf-8") as f:
            ids.update(int(v) for v in json.load(f).values())
    return sorted(ids)


def fetch_intros(page_ids):
    """{page_id: (title, intro text)} for up to 20 ids."""
    query = urllib.parse.urlencode({
        "action": "query", "prop": "extracts", "exintro": 1, "explaintext": 1,
        "exlimit": 20, "pageids": "|".join(str(i) for i in page_ids), "format": "json",
    })
    req = urllib.request.Request(API + "?" + query, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        pages = json.load(resp).get("query", {}).get("pages", {})
    return {int(k): (p.get("title", ""), p.get("extract", "") or "") for k, p in pages.items() if "missing" not in p}


def long_enough(intro):
    sentences = [s for s in re.split(r"(?<=[.!?])\s+", intro.strip()) if len(s) > 20]
    return len(sentences) >= MIN_SENTENCES


def pick_day(pool, recently_used, rng):
    candidates = [i for i in pool if i not in recently_used]
    rng.shuffle(candidates)
    picked, titles = [], []
    for start in range(0, len(candidates), 20):
        batch = candidates[start:start + 20]
        intros = fetch_intros(batch)
        for page_id in batch:  # keep the shuffled order
            if page_id in intros and long_enough(intros[page_id][1]):
                picked.append(page_id)
                titles.append(intros[page_id][0])
                if len(picked) == IDS_PER_DAY:
                    return picked, titles
    raise RuntimeError("Not enough usable articles left in the official playlists")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--schedule", required=True, help="schedule.json to update (created if missing)")
    parser.add_argument("--days-ahead", type=int, default=7)
    parser.add_argument("--reroll", action="append", default=[], help="YYYY-MM-DD to pick a new set for")
    args = parser.parse_args()

    path = pathlib.Path(args.schedule)
    schedule = {"version": 1, "days": {}}
    if path.exists():
        with open(path, encoding="utf-8") as f:
            schedule = json.load(f)
    days = schedule.setdefault("days", {})

    today = datetime.datetime.now(datetime.timezone.utc).date()
    pool = official_ids()
    rng = random.SystemRandom()
    changed = []
    for offset in range(args.days_ahead + 1):
        date = (today + datetime.timedelta(days=offset)).isoformat()
        if date in days and date not in args.reroll:
            continue
        cutoff = (today - datetime.timedelta(days=NO_REPEAT_DAYS)).isoformat()
        recently_used = {i for d, e in days.items() if d >= cutoff and d != date for i in e.get("ids", [])}
        ids, titles = pick_day(pool, recently_used, rng)
        # "titles" is only for whoever reads the file - the game uses "ids".
        days[date] = {"ids": ids, "titles": titles}
        changed.append(date)

    if not changed:
        print("Schedule already filled through", (today + datetime.timedelta(days=args.days_ahead)).isoformat())
        return 0
    schedule["days"] = dict(sorted(days.items()))
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(schedule, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print("Added/rerolled:", ", ".join(changed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
