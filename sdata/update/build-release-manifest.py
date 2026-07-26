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
            patch, take a white dot, and be filtered out entirely for anyone
            who asked to hear about security releases only. Because the
            manifest is rebuilt from tags, a wrong call is fixed by retagging.

  summary   the subject of the commit the tag points at
  changes   the subjects of the commits since the previous release

Usage:
  build-release-manifest.py [--repo PATH] [--limit N] [-o releases.json]
"""

import argparse
import json
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

    The desktop escalates the dot colour by how long a release has been out, so
    this wants to be when the tag was created, not when the commit under it
    happened to be written. git reports the commit date for lightweight tags,
    which is the best available answer for those.
    """
    return git(repo, "for-each-ref", "--format=%(creatordate:short)",
               f"refs/tags/{tag}").strip()


def tag_subject(repo, tag):
    """The headline for a release, skipping a merge commit if the tag sits on one."""
    return git(repo, "log", "-1", "--no-merges", "--format=%s", tag).strip()


def subjects_between(repo, previous, tag):
    """The commits a release introduced.

    --first-parent is what keeps this honest. This fork merges from end-4
    upstream, and a plain log would list every commit those merges bring in —
    hundreds of someone else's subjects, crowding out the actual changes.

    The first release has no predecessor to diff against, and walking all the
    way back would sweep in the entire history, so it stands alone.
    """
    if not previous:
        return [tag_subject(repo, tag)]
    out = git(repo, "log", "--first-parent", "--no-merges", "--format=%s",
              f"{previous}..{tag}")
    return [line.strip() for line in out.splitlines() if line.strip()]


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


def build(repo, limit):
    tags = release_tags(repo)
    if not tags:
        raise SystemExit("no release tags found")

    releases = []
    for index, (version, tag) in enumerate(tags):
        previous_version, previous_tag = tags[index - 1] if index else (None, None)
        subjects = subjects_between(repo, previous_tag, tag)
        summary = humanise(tag_subject(repo, tag))
        # The tag's own subject is the summary, so leaving it in changes too
        # would make every consumer strip it back out — and it would cost one
        # of the twenty slots on every release.
        changes = [c for c in (humanise(s) for s in subjects) if c != summary]
        releases.append({
            "version": tag,
            "date": tag_date(repo, tag),
            "kind": classify(repo, tag, version, previous_version, subjects),
            "summary": summary,
            "changes": changes[:20],
        })

    releases.reverse()
    if limit:
        releases = releases[:limit]
    return {
        "schema": 1,
        "latest": releases[0]["version"],
        "releases": releases,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=".")
    parser.add_argument("--limit", type=int, default=20,
                        help="keep only the newest N releases (0 for all)")
    parser.add_argument("-o", "--output", default="-")
    args = parser.parse_args()

    manifest = build(args.repo, args.limit)
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
