#!/usr/bin/env python3
"""Check that MainstreamHome is MainstreamWorkstation plus folder sharing.

Settings > Sharing moves a network the user trusts from MainstreamWorkstation
into MainstreamHome, so anything else that differs between the two zones would
change more than sharing on that network. MainstreamHome has to be
MainstreamWorkstation with its short name changed and exactly two rules
appended: SMB (445/tcp) from the mainstream-lan4 and mainstream-lan6 ipsets.

The ipsets have to hold the same ranges as `hosts allow` in the smb.conf
template as well, so the firewall and Samba agree on what a local address is.

Usage: check-home-zone.py [repo root]
"""

import difflib
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

HOME_SHORT = "Mainstream Home"
RULES = (("ipv4", "mainstream-lan4"), ("ipv6", "mainstream-lan6"))
# The loopback addresses in `hosts allow` let this computer reach itself; no
# packet from them ever arrives through a zone.
LOOPBACK = {"127.0.0.1", "::1"}


def normalized(el):
    """The element as one line, without the whitespace between tags."""
    copy = ET.Element(el.tag, dict(sorted(el.attrib.items())))
    copy.text = (el.text or "").strip() or None
    for child in el:
        copy.append(normalized(child))
    return copy


def lines(elements):
    return [ET.tostring(normalized(e), encoding="unicode") for e in elements]


def sharing_rule(family, ipset):
    rule = ET.Element("rule", family=family)
    ET.SubElement(rule, "source", ipset=ipset)
    ET.SubElement(rule, "port", port="445", protocol="tcp")
    ET.SubElement(rule, "accept")
    return rule


def check_zone(workstation, home):
    ws = ET.parse(workstation).getroot()
    hm = ET.parse(home).getroot()
    expected = []
    for child in ws:
        if child.tag == "short":
            child = ET.Element("short")
            child.text = HOME_SHORT
        expected.append(child)
    expected += [sharing_rule(f, s) for f, s in RULES]

    problems = []
    if dict(ws.attrib) != dict(hm.attrib):
        problems.append(f"<zone> attributes differ: {dict(ws.attrib)} vs {dict(hm.attrib)}")
    want, got = lines(expected), lines(hm)
    if want != got:
        diff = difflib.unified_diff(want, got, "expected", str(home), lineterm="")
        problems.append("\n".join(diff))
    return problems


def ipset_entries(path):
    return {e.text.strip() for e in ET.parse(path).getroot().iter("entry")}


def check_ranges(pkg):
    allowed = None
    for line in (pkg / "smb.conf").read_text().splitlines():
        key, _, value = line.partition("=")
        if key.strip() == "hosts allow":
            allowed = set(value.split()) - LOOPBACK
    if allowed is None:
        return ["the smb.conf template has no hosts allow line"]
    in_ipsets = set()
    for _, name in RULES:
        in_ipsets |= ipset_entries(pkg / f"{name}.xml")
    if allowed != in_ipsets:
        return [
            "hosts allow and the ipsets differ: "
            f"only in hosts allow {sorted(allowed - in_ipsets)}, "
            f"only in the ipsets {sorted(in_ipsets - allowed)}"
        ]
    return []


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
    pkg = root / "sdata/dist-arch/mainstream-system"
    zone = check_zone(root / "sdata/firewalld/MainstreamWorkstation.xml", pkg / "MainstreamHome.xml")
    ranges = check_ranges(pkg)
    for p in zone + ranges:
        print(p, file=sys.stderr)
    if zone:
        print(
            "MainstreamHome.xml must be MainstreamWorkstation.xml with the short name "
            f"'{HOME_SHORT}' and the two sharing rules appended.",
            file=sys.stderr,
        )
    if zone or ranges:
        return 1
    print("MainstreamHome matches MainstreamWorkstation plus the sharing rules.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
