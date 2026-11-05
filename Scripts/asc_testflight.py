#!/usr/bin/env python3
"""After an upload: wait for App Store Connect to finish processing the build, put it in the internal tester
group, and set What to Test. With EXTERNAL_GROUP set, it also adds the build to that external group and submits it
for Beta App Review. It never submits for App Store review, and never adds or removes testers.

Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (the .p8 file), APP_ID, BUILD_NUMBER.
Optional: TESTER_GROUP (a group name; default is every internal group), EXTERNAL_GROUP (an external group name),
WHAT_TO_TEST_FILE, WAIT_MINUTES (default 30).
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

    # External group and Beta App Review. TestFlight's auto-notify on the group decides who hears; nothing here does.
    external = os.environ.get("EXTERNAL_GROUP")
    if not external:
        return 0
    if not (path and os.path.exists(path)):
        print("::warning::No What to Test file; not sending build %s to %s" % (number, external))
        return 1
    group = next((g for g in groups.get("data", [])
                  if not g["attributes"].get("isInternalGroup") and g["attributes"].get("name") == external), None)
    if not group:
        print("::warning::No external TestFlight group named %r" % external)
        return 1
    status, data = call("POST", "/betaGroups/%s/relationships/builds" % group["id"], {"data": [{"type": "builds", "id": build}]})
    if status not in (200, 204):
        print("::warning::Could not add build %s to %s (HTTP %s): %s" % (number, external, status, errors(data)))
        return 1
    print("Added to %s: ok" % external)
    status, data = call("POST", "/betaAppReviewSubmissions",
                        {"data": {"type": "betaAppReviewSubmissions",
                                  "relationships": {"build": {"data": {"type": "builds", "id": build}}}}})
    if status in (200, 201):
        print("::notice::Build %s submitted for Beta App Review" % number)
    elif status == 409 or "already" in errors(data).lower():
        print("::notice::Build %s was already submitted or approved for beta: %s" % (number, errors(data)))
    else:
        print("::warning::Beta App Review submission failed (HTTP %s): %s" % (status, errors(data)))
        return 1
    return 0


def errors(data):
    return "; ".join(e.get("detail") or e.get("title", "") for e in data.get("errors", []))[:300]


if __name__ == "__main__":
    sys.exit(main())
