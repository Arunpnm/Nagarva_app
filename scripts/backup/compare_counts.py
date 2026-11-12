#!/usr/bin/env python3
"""Restore check for the nightly backup (.github/workflows/db-backup.yml).

usage: compare_counts.py counts-before.tsv counts-after.tsv restored.tsv

Each file is "table<TAB>rows" per line. The live database keeps changing
while the dump runs, so a restored table passes when its row count lies
between the live count just before the dump and just after it. Fails
(exit 1) when:
  * a table is in the live database but missing from the restored copy;
  * a restored count is outside [before, after] (either order);
  * the live database had rows in total but nothing came back.
Prints only table names and numbers -- never row contents.
"""
import sys


def read(path):
    out = {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            name, _, n = line.partition("\t")
            out[name] = int(n)
    return out


def compare(before, after, restored):
    problems = []
    for table in sorted(set(before) | set(after)):
        lo_hi = [x for x in (before.get(table), after.get(table)) if x is not None]
        lo, hi = min(lo_hi), max(lo_hi)
        if table not in restored:
            # A table created during the dump window may be absent.
            if table in before:
                problems.append(f"{table}: missing from the restored copy (live {lo}..{hi})")
            continue
        got = restored[table]
        if not (lo <= got <= hi):
            problems.append(f"{table}: restored {got}, live {lo}..{hi}")
    live_total = sum(before.values())
    got_total = sum(restored.get(t, 0) for t in before)
    if live_total > 0 and got_total == 0:
        problems.append("nothing was restored")
    return problems, live_total, got_total


def main(argv):
    if len(argv) != 4:
        print(__doc__)
        return 2
    before, after, restored = (read(p) for p in argv[1:])
    problems, live_total, got_total = compare(before, after, restored)
    print(f"tables: {len(before)} live, {len(restored)} restored; "
          f"rows: {live_total} live before dump, {got_total} restored")
    if problems:
        print("RESTORE CHECK FAILED:")
        for p in problems:
            print("  " + p)
        return 1
    print("Restore check passed: every table came back with its rows.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
