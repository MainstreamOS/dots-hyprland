#!/usr/bin/env python3
"""Build releases.json, the file the desktop checks to find out about new releases.

Run from a clone of this repo after tagging, then commit the output to the
website repo so it is served from https://mainstreamos.org/releases.json.

Everything is derived from the tags themselves so the manifest can't drift
from what was actually released:

  kind      declared, when the annotated tag carries a Release-Kind trailer:

                git tag -a 1.1.0 -m "Whatever the release is

                Release-Kind: security"

            otherwise inferred — security when a commit in the range is a
            security: commit, feature when the minor version moved, else patch.

            Declare it for anything that matters. Inference only reads commit
            subjects, so a security fix committed as "fix: ..." would ship as a
            patch and be understated wherever the kind is used. Because the
            manifest is rebuilt from tags, a wrong call is fixed by retagging.

  summary   the subject of the commit the tag points at
  changes   the subjects of the commits since the previous release

Commit subjects are a poor changelog for a release whose story isn't told one
commit at a time — most of all the first one, which has no predecessor tag to
diff against and so derives nothing at all. release-notes.json overrides either
field for any version:

    {"1.0.0": {"summary": "...", "changes": ["...", "..."]}}

Only the versions named there are affected, and only the keys given, so the
derived text stays the default and every deviation from it is visible in one
file. Kind is deliberately not overridable — the tag stays the source of truth
for how important a release is.

A release may also carry a "name". Nothing derives one, so it appears only for
the releases given one, and the pages that show it leave the slot out entirely
for the rest.

Alongside that human-facing pair, every release also carries the unedited
commit range behind it:

  commits      "<short sha> <subject>" for each first-parent commit in the
               release, in order, capped at TECH_CAP
  commitNotes  sha -> commit body, only for the commits that wrote one
  merges       merges the first-parent walk stepped over, omitted when none
  commitsTotal the real commit count, present only when the cap truncated the
               list, so a shortened list can't read as the whole story

These three are for the technical track on the website, which is off by
default and opt-in per reader. The desktop never reads them; it builds its
notification from summary and changes alone. Like kind, they are deliberately
not overridable from release-notes.json — their whole value is that anyone can
reproduce them with one git log, so there is nowhere to write prose that only
looks like a machine record.

Per release:
  1. Tag dots, with a Release-Kind trailer when inference would understate it.
  2. Write summary and changes into release-notes.json if the commit subjects
     don't tell the release's story on their own. Nothing technical goes there;
     the commit range is already carried automatically.
  3. Run this script. No new arguments.
  4. Copy releases.json into the website repo and commit it by path.
  5. Tag archiso with the same version, on the commit the ISO was built from.
     From 1.1.0 onward. Nothing reads those tags yet — they exist so installer
     and ISO commits can join the technical track later with a real range.
     Never backfill one by date: archiso mirrors dots promptly, including work
     that is on the branch but in no release, so a date-derived range claims
     unreleased changes shipped.

Usage:
  build-release-manifest.py [--repo PATH] [--limit N] [--notes PATH] [-o releases.json]
"""

import argparse
import json
import pathlib
import re
import subprocess
import sys

SEMVER = re.compile(r"^(\d{1,2})\.(\d+)\.(\d+)$")
# Conventional prefixes carry no meaning for a user reading a changelog. The
# optional (scope) matters: "fix(ii): ..." is as common here as "fix: ...".
PREFIX = re.compile(r"^[a-z0-9][a-z0-9 /+-]{0,24}(\([^)]{0,32}\))?:\s*")
SECURITY_PREFIX = re.compile(r"^security(\([^)]*\))?\s*:", re.IGNORECASE)
RELEASE_KIND = re.compile(r"^Release-Kind:\s*(\w+)\s*$", re.IGNORECASE | re.MULTILINE)
KINDS = ("security", "feature", "patch")
# Every installed desktop fetches this manifest on a timer, so the technical
# track is bounded. Neither cap has ever been reached: the largest release so
# far is six commits, three of which carry a body.
TECH_CAP = 40
BODY_CAP = 1000


def git(repo, *args):
    result = subprocess.run(["git", "-C", repo, *args],
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout


def release_tags(repo):
    tags = []
    for line in git(repo, "tag", "-l").splitlines():
        match = SEMVER.match(line.strip())
        if match:
            tags.append((tuple(int(p) for p in match.groups()), line.strip()))
    tags.sort()
    return tags


def tag_date(repo, tag):
    """When the release was published.

    The publication date, not the authorship date: a tag can point at a commit
    written weeks earlier, and consumers age a release from when it shipped.
    git reports the commit date for lightweight tags, which is the best
    available answer for those.
    """
    return git(repo, "for-each-ref", "--format=%(creatordate:short)",
               f"refs/tags/{tag}").strip()


def tag_subject(repo, tag):
    """The headline for a release, skipping a merge commit if the tag sits on one."""
    return git(repo, "log", "-1", "--no-merges", "--format=%s", tag).strip()


def commits_between(repo, previous, tag):
    """The commits a release introduced, as (sha, subject, body) triples.

    --first-parent is what keeps this honest. This fork merges from end-4
    upstream, and a plain log would list every commit those merges bring in —
    hundreds of someone else's subjects, crowding out the actual changes.

    The first release has no predecessor to diff against, and walking all the
    way back would sweep in the entire history, so it has no range at all.

    The record separator leads each entry rather than trailing it: %b runs to
    the end of the record, so a trailing separator would let one commit's body
    run into the next commit's sha.
    """
    if not previous:
        return []
    out = git(repo, "log", "--first-parent", "--no-merges",
              "--format=%x1e%h%x1f%s%x1f%b", f"{previous}..{tag}")
    commits = []
    for record in out.split("\x1e"):
        if not record.strip():
            continue
        sha, subject, body = (record.split("\x1f") + ["", ""])[:3]
        commits.append((sha.strip(), subject.strip(), body.strip()))
    return commits


def merges_between(repo, previous, tag):
    """How many merges the first-parent walk stepped over.

    The commit list looks exhaustive, so on the day an upstream merge lands
    inside a release range it has to be able to say that it isn't.
    """
    if not previous:
        return 0
    out = git(repo, "log", "--first-parent", "--merges", "--format=%h",
              f"{previous}..{tag}")
    return len([line for line in out.splitlines() if line.strip()])


def humanise(subject):
    """Drop the conventional prefix and capitalise, so the changelog reads as
    prose rather than as commit log."""
    text = PREFIX.sub("", subject).strip()
    return text[:1].upper() + text[1:] if text else text


def declared_kind(repo, tag):
    """What the tag says it is, if it says anything.

    Inference below can only under-report — it reads commit subjects, and a
    release whose importance isn't spelled out in one gets downgraded. A
    trailer on the tag is the releaser saying it outright.
    """
    body = git(repo, "for-each-ref", "--format=%(contents)", f"refs/tags/{tag}")
    match = RELEASE_KIND.search(body)
    if not match:
        return None
    kind = match.group(1).lower()
    if kind not in KINDS:
        print(f"warning: {tag} declares unknown Release-Kind {match.group(1)!r}; inferring instead",
              file=sys.stderr)
        return None
    return kind


def classify(repo, tag, version, previous_version, subjects):
    declared = declared_kind(repo, tag)
    if declared:
        return declared
    if any(SECURITY_PREFIX.match(s) for s in subjects):
        return "security"
    if previous_version is None or version[:2] != previous_version[:2]:
        return "feature"
    return "patch"


def load_notes(path):
    """Curated overrides, keyed by version. Absent file means none."""
    if not path or not pathlib.Path(path).is_file():
        return {}
    with open(path) as handle:
        notes = json.load(handle)
    if not isinstance(notes, dict):
        raise SystemExit(f"{path}: expected an object keyed by version")
    return notes


def build(repo, limit, notes):
    tags = release_tags(repo)
    if not tags:
        raise SystemExit("no release tags found")

    # A version can be written up before it is cut, so the website can show
    # what is coming. Such an entry has to supply its own date and kind, since
    # there is no tag to read them from, and it carries no commit range.
    unknown = set(notes) - {tag for _, tag in tags}
    upcoming = []
    for version in sorted(unknown, key=lambda v: [int(p) for p in v.split(".")]
                          if SEMVER.match(v) else [0], reverse=True):
        note = notes[version]
        if "date" in note and "kind" in note:
            entry = {
                "version": version,
                "date": note["date"],
                "kind": note["kind"],
                "summary": note.get("summary", ""),
                "changes": [str(c) for c in note.get("changes", [])],
                "commits": [],
                "unreleased": True,
            }
            if note.get("name"):
                entry["name"] = str(note["name"])
            upcoming.append(entry)
        else:
            print(f"warning: release-notes has no matching tag for {version!r} and no "
                  f"date/kind to publish it as upcoming; ignoring", file=sys.stderr)

    releases = []
    for index, (version, tag) in enumerate(tags):
        previous_version, previous_tag = tags[index - 1] if index else (None, None)
        commits = commits_between(repo, previous_tag, tag)
        # A first release has no range, so its own subject is all there is to
        # classify on. Keyed off the missing predecessor rather than an empty
        # list, so a tag placed on the same commit as the one before it
        # reports an honest empty release instead of quoting itself.
        subjects = [subject for _, subject, _ in commits]
        if previous_tag is None:
            subjects = [tag_subject(repo, tag)]
        summary = humanise(tag_subject(repo, tag))
        # The tag's own subject is the summary, so leaving it in changes too
        # would make every consumer strip it back out — and it would cost a
        # slot on every release.
        changes = [c for c in (humanise(s) for s in subjects) if c != summary]

        # A derived list is however long the range happened to be, so it is
        # capped. A curated one is exactly what someone chose to say, so it is
        # not — truncating that would drop deliberate text on the floor.
        cap = len(changes)
        note = notes.get(tag, {})
        summary = note.get("summary", summary)
        if "changes" in note:
            changes = [str(c) for c in note["changes"]]
            cap = len(changes)
        else:
            cap = 20

        entry = {
            "version": tag,
            "date": tag_date(repo, tag),
            "kind": classify(repo, tag, version, previous_version, subjects),
            "summary": summary,
            "changes": [c for c in changes if c != summary][:cap],
            "commits": [f"{sha} {subject}" for sha, subject, _ in commits[:TECH_CAP]],
        }
        if note.get("name"):
            entry["name"] = str(note["name"])
        # A capped list still looks exhaustive, so say when it isn't. The
        # compare link on the page reaches the rest.
        if len(commits) > TECH_CAP:
            entry["commitsTotal"] = len(commits)
        bodies = {sha: body[:BODY_CAP] for sha, _, body in commits[:TECH_CAP] if body}
        if bodies:
            entry["commitNotes"] = bodies
        skipped = merges_between(repo, previous_tag, tag)
        if skipped:
            entry["merges"] = skipped
        releases.append(entry)

    releases.reverse()
    # latest names the newest RELEASED version and never an upcoming one. The
    # desktop treats anything in the list that is newer than what is installed
    # as available, so naming a version that has no tag would announce an
    # update nobody can install.
    latest = releases[0]["version"] if releases else ""
    releases = upcoming + releases
    if limit:
        releases = releases[:limit]
    return {
        "latest": latest,
        "releases": releases,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=".")
    parser.add_argument("--limit", type=int, default=20,
                        help="keep only the newest N releases (0 for all)")
    parser.add_argument("--notes", default=str(pathlib.Path(__file__).with_name("release-notes.json")),
                        help="curated per-version overrides (default: alongside this script)")
    parser.add_argument("-o", "--output", default="-")
    args = parser.parse_args()

    manifest = build(args.repo, args.limit, load_notes(args.notes))
    text = json.dumps(manifest, indent=2) + "\n"
    if args.output == "-":
        sys.stdout.write(text)
    else:
        with open(args.output, "w") as handle:
            handle.write(text)
        print(f"wrote {args.output}: latest {manifest['latest']}, "
              f"{len(manifest['releases'])} releases", file=sys.stderr)


if __name__ == "__main__":
    main()
