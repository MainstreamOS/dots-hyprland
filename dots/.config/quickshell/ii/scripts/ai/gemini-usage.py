#!/usr/bin/env python3
# Prints exactly one JSON object: the quota of the signed-in Antigravity
# account, or {"error": "no-login" | "auth" | "network" | "unexpected"}.
# Credentials are only read: a refreshed token lives in memory for this run.
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

USER_AGENT = "antigravity/1.3.1 linux/amd64"
MODELS_URL = "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels"
TOKEN_URL = "https://oauth2.googleapis.com/token"
# Antigravity's own OAuth client, read from the installed CLI rather than kept
# here. The pair that worked is remembered until the CLI changes.
CLIENT_ID_RE = rb"\d{6,}-[0-9a-z]{32}\.apps\.googleusercontent\.com"
CLIENT_SECRET_RE = rb"GOCSPX-[A-Za-z0-9_-]{28}"
CLIENT_CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
                            "quickshell", "ai", "agy-oauth-client.json")

# Quota fields that name a weekly window explicitly. Nothing else is reported
# as weekly, since another model's bucket is not a seven-day window.
WEEKLY_KEYS = ("weeklyQuotaInfo", "weeklyQuota", "weekly")
WEEKLY_WINDOW_KEYS = ("window", "quotaWindow", "period")
WEEKLY_WINDOW_VALUES = ("WEEKLY", "WEEK", "7D", "604800S")


class Failure(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.code = code


def get_credentials():
    try:
        raw = subprocess.run(
            ["secret-tool", "lookup", "service", "gemini", "username", "antigravity"],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            timeout=15, check=False,
        ).stdout.decode("utf-8").strip()
        if raw:
            tok = json.loads(raw).get("token", {})
            if tok.get("access_token") or tok.get("refresh_token"):
                return tok.get("access_token"), tok.get("refresh_token")
    except Exception:
        pass

    creds_path = os.path.expanduser("~/.gemini/oauth_creds.json")
    try:
        with open(creds_path) as f:
            d = json.load(f)
        return d.get("access_token"), d.get("refresh_token")
    except Exception:
        return None, None


def client_pairs(use_cache=True):
    """Candidate (id, secret) pairs, the remembered one alone when it still applies."""
    path = shutil.which("agy")
    if not path:
        return [], None, False
    path = os.path.realpath(path)
    try:
        st = os.stat(path)
    except OSError:
        return [], None, False
    stamp = [path, st.st_size, st.st_mtime_ns]
    if use_cache:
        try:
            with open(CLIENT_CACHE) as f:
                cached = json.load(f)
            if cached.get("stamp") == stamp and len(cached.get("pair", [])) == 2:
                return [tuple(cached["pair"])], stamp, True
        except Exception:
            pass
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return [], None, False
    ids = dict.fromkeys(m.decode() for m in re.findall(CLIENT_ID_RE, data))
    secrets = dict.fromkeys(m.decode() for m in re.findall(CLIENT_SECRET_RE, data))
    return [(i, s) for i in ids for s in secrets], stamp, False


def remember_client(pair, stamp):
    try:
        os.makedirs(os.path.dirname(CLIENT_CACHE), exist_ok=True)
        fd = os.open(CLIENT_CACHE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            json.dump({"stamp": stamp, "pair": list(pair)}, f)
    except OSError:
        pass


def refresh_with(rf, client):
    """The new access token, or None when this client is not the one the token belongs to."""
    params = {
        "client_id": client[0],
        "client_secret": client[1],
        "grant_type": "refresh_token",
        "refresh_token": rf,
    }
    req = urllib.request.Request(
        TOKEN_URL,
        data=urllib.parse.urlencode(params).encode("utf-8"),
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            token = json.loads(resp.read().decode("utf-8")).get("access_token")
    except urllib.error.HTTPError as e:
        try:
            error = json.loads(e.read().decode("utf-8")).get("error", "")
        except Exception:
            error = ""
        if error in ("invalid_client", "unauthorized_client"):
            return None
        raise Failure("auth")
    except (urllib.error.URLError, OSError):
        raise Failure("network")
    if not token:
        raise Failure("auth")
    return token


def refresh_token(rf):
    pairs, stamp, cached = client_pairs()
    while True:
        for pair in pairs:
            token = refresh_with(rf, pair)
            if token:
                if not cached:
                    remember_client(pair, stamp)
                return token
        if not cached:
            raise Failure("auth")
        pairs, stamp, cached = client_pairs(use_cache=False)


def fetch_models(access_token):
    req = urllib.request.Request(
        MODELS_URL,
        data=b"{}",
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
            "User-Agent": USER_AGENT,
        },
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read().decode("utf-8"))


def fetch_with_refresh(tok, rf):
    if tok:
        try:
            return fetch_models(tok)
        except urllib.error.HTTPError as e:
            if e.code != 401:
                raise Failure("network")
        except (urllib.error.URLError, OSError):
            raise Failure("network")
    if not rf:
        raise Failure("auth")
    try:
        return fetch_models(refresh_token(rf))
    except urllib.error.HTTPError as e:
        raise Failure("auth" if e.code == 401 else "network")
    except (urllib.error.URLError, OSError):
        raise Failure("network")


def utilization(remaining):
    return round(max(0.0, min(100.0, (1.0 - remaining) * 100.0)), 1)


def weekly_window(quota):
    for key in WEEKLY_KEYS:
        info = quota.get(key)
        if isinstance(info, dict) and info.get("remainingFraction") is not None:
            return {"utilization": utilization(info["remainingFraction"]), "resets_at": info.get("resetTime")}
    for key in WEEKLY_WINDOW_KEYS:
        if str(quota.get(key, "")).upper() in WEEKLY_WINDOW_VALUES and quota.get("remainingFraction") is not None:
            return {"utilization": utilization(quota["remainingFraction"]), "resets_at": quota.get("resetTime")}
    return None


def usage(target_model):
    tok, rf = get_credentials()
    if not tok and not rf:
        raise Failure("no-login")
    res = fetch_with_refresh(tok, rf)

    models = res.get("models", {}) if isinstance(res, dict) else {}
    if not isinstance(models, dict):
        models = {}
    quota = None

    # Priority lookup based on active model if requested
    target_lower = target_model.lower()
    if "pro" in target_lower:
        preferred = ["gemini-3.1-pro-low", "gemini-3.1-pro-high", "gemini-pro-agent", "gemini-2.5-pro"]
    elif "flash" in target_lower:
        preferred = ["gemini-3.8-flash-tiered", "gemini-3.8-flash-medium", "gemini-3.6-flash-high", "gemini-3.1-flash-lite"]
    else:
        preferred = ["gemini-3.8-flash-tiered", "gemini-3.1-pro-low", "gemini-3.6-flash-high", "gemini-pro-agent"]

    for k in preferred:
        if isinstance(models.get(k), dict) and models[k].get("quotaInfo"):
            quota = models[k]["quotaInfo"]
            break

    if not quota:
        for m in models.values():
            qi = m.get("quotaInfo") if isinstance(m, dict) else None
            if qi and qi.get("remainingFraction") is not None:
                quota = qi
                break

    session = None
    weekly = None
    if quota:
        rem = quota.get("remainingFraction")
        if rem is not None:
            session = {"utilization": utilization(rem), "resets_at": quota.get("resetTime")}
        weekly = weekly_window(quota)

    return {"planType": "google_account", "session": session, "weekly": weekly}


def main():
    try:
        out = usage(sys.argv[1] if len(sys.argv) > 1 else "")
    except Failure as e:
        out = {"error": e.code}
    except Exception:
        out = {"error": "unexpected"}
    print(json.dumps(out), flush=True)


if __name__ == "__main__":
    main()
