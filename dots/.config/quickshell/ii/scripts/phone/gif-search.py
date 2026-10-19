#!/usr/bin/env python3
"""
gif-search.py - Search Tenor for animated GIFs or return trending GIFs.
Used by PhoneGifPicker.qml for the Phone tab.
Usage:
  gif-search.py [query]
Output:
  JSON array of GIF objects on stdout:
  [{"url": "...", "thumb": "..."}, ...]
"""
import sys
import re
import json
import urllib.request
import urllib.parse

def search_gifs(query="", limit=24):
    query = query.strip()
    if not query:
        url = "https://tenor.com/search/trending-gifs"
    else:
        q_clean = urllib.parse.quote(query.replace(" ", "-"))
        url = f"https://tenor.com/search/{q_clean}-gifs"

    try:
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"}
        )
        with urllib.request.urlopen(req, timeout=4.5) as resp:
            html = resp.read(4 << 20).decode("utf-8", errors="ignore")  # the first results are near the top

        # Find direct tenor gif URLs
        gifs = re.findall(r'https://media\.tenor\.com/[^\"\'\s<>]+?\.gif', html)
        unique = list(dict.fromkeys(gifs))

        results = []
        for g in unique[:limit]:
            results.append({
                "url": g,
                "thumb": g
            })
        return results
    except Exception as e:
        return []

def main():
    query = " ".join(sys.argv[1:]).strip()
    results = search_gifs(query)
    sys.stdout.write(json.dumps(results) + "\n")
    sys.stdout.flush()

if __name__ == "__main__":
    main()
