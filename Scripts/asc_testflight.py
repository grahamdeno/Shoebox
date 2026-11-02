#!/usr/bin/env python3
"""After an upload: wait for App Store Connect to finish processing the build, put it in the internal tester
group, and set What to Test. It never submits anything for review.

Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (the .p8 file), APP_ID, BUILD_NUMBER.
Optional: TESTER_GROUP (a group name; default is every internal group), WHAT_TO_TEST_FILE, WAIT_MINUTES (default 30).
Needs: pip install pyjwt cryptography
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"


def token():
    key = open(os.environ["ASC_KEY_PATH"]).read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1000, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None, ok=(200, 201, 204)):
    req = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            raw = res.read()
            return res.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        if e.code in ok:
            return e.code, {}
        return e.code, (json.loads(raw) if raw else {})


def main():
    app, number = os.environ["APP_ID"], os.environ["BUILD_NUMBER"]
    deadline = time.time() + 60 * int(os.environ.get("WAIT_MINUTES", "30"))
    build = None
    while time.time() < deadline:
        q = urllib.parse.urlencode({"filter[app]": app, "filter[version]": number, "limit": 5})
        status, data = call("GET", "/builds?" + q)
        rows = data.get("data", []) if status == 200 else []
        if rows:
            state = rows[0]["attributes"].get("processingState")
            print("Build %s is %s" % (number, state))
            if state == "VALID":
                build = rows[0]["id"]
                break
            if state in ("FAILED", "INVALID"):
                print("::error::App Store Connect could not process build %s (%s)" % (number, state))
                return 1
        else:
            print("Build %s is not listed yet" % number)
        time.sleep(60)
    if not build:
        print("::warning::Build %s was not ready after the wait. Add it to the tester group by hand." % number)
        return 1

    # What to Test.
    path = os.environ.get("WHAT_TO_TEST_FILE")
    if path and os.path.exists(path):
        text = open(path).read().strip()[:4000]
        body = {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": text},
                         "relationships": {"build": {"data": {"type": "builds", "id": build}}}}}
        status, data = call("POST", "/betaBuildLocalizations", body)
        if status == 409:
            status, existing = call("GET", "/builds/%s/betaBuildLocalizations" % build)
            for row in existing.get("data", []):
                if row["attributes"].get("locale") == "en-US":
                    call("PATCH", "/betaBuildLocalizations/" + row["id"],
                         {"data": {"type": "betaBuildLocalizations", "id": row["id"], "attributes": {"whatsNew": text}}})
        print("What to Test set")

    # Internal tester groups.
    status, groups = call("GET", "/apps/%s/betaGroups?limit=50" % app)
    wanted = os.environ.get("TESTER_GROUP")
    chosen = [g for g in groups.get("data", [])
              if g["attributes"].get("isInternalGroup") and (not wanted or g["attributes"].get("name") == wanted)]
    if not chosen:
        print("::warning::No internal tester group found. Make one in App Store Connect (TestFlight > Internal Testing).")
        return 1
    for g in chosen:
        status, data = call("POST", "/betaGroups/%s/relationships/builds" % g["id"], {"data": [{"type": "builds", "id": build}]})
        print("Added to %s: %s" % (g["attributes"].get("name"), "ok" if status in (200, 204) else "HTTP %s" % status))
        if status not in (200, 204):
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
