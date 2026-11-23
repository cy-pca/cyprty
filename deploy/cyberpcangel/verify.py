#!/usr/bin/env python3
"""Check the live cyberpcangel.com/cyprty site against a staged payload.

    deploy/cyberpcangel/verify.py PAYLOAD [BASE_URL]

PAYLOAD is stage.sh's OUT. Every staged file must be served byte for byte, uncompressed, and a
script as JavaScript (the site sends nosniff, and an AudioWorklet module, cvc-audio-worklet.js,
loads only as JavaScript); the site's directory URL must serve index.html with the cross-origin
isolation headers, and the URL without the trailing slash must redirect to it. Python's urllib
only (the CI runner's curl is broken).
"""
import pathlib
import sys
import urllib.error
import urllib.request

SITE = "cyprty"
JS_TYPES = ("text/javascript", "application/javascript")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def get(url, follow=True):
    req = urllib.request.Request(url, headers={"Accept-Encoding": "identity",
                                               "Cache-Control": "no-cache"})
    opener = urllib.request.build_opener() if follow else urllib.request.build_opener(NoRedirect)
    try:
        with opener.open(req, timeout=60) as r:
            return r.status, r.headers, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.headers, b""


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    root = pathlib.Path(sys.argv[1]) / SITE
    base = (sys.argv[2] if len(sys.argv) == 3 else "https://cyberpcangel.com").rstrip("/")
    ok = True

    def check(cond, what):
        nonlocal ok
        print(f"  {'OK  ' if cond else 'FAIL'} {what}")
        ok = ok and cond

    print(f"{base}/{SITE}/")
    status, headers, body = get(f"{base}/{SITE}/")
    check(status == 200 and body == (root / "index.html").read_bytes(), f"/{SITE}/ serves index.html")
    check(headers.get("Cross-Origin-Opener-Policy", "") == "same-origin", "cross-origin isolated")
    status, headers, _ = get(f"{base}/{SITE}", follow=False)
    check(status in (301, 302) and headers.get("Location", "").endswith(f"/{SITE}/"),
          f"/{SITE} redirects to /{SITE}/")
    for f in sorted(p for p in root.rglob("*") if p.is_file()):
        rel = f.relative_to(root).as_posix()
        status, headers, body = get(f"{base}/{SITE}/{rel}")
        check(status == 200 and body == f.read_bytes(), rel)
        if status == 200 and f.suffix == ".js":
            ctype = headers.get("Content-Type", "").split(";")[0].strip().lower()
            check(ctype in JS_TYPES, f"{rel} is served as JavaScript ({ctype or 'no type'})")
    # What a browser does on its next visit: arigl.wasm compressed, then revalidated with the ETag
    # it got. A 200 here means every visit downloads the client again.
    wasm = f"{base}/{SITE}/arigl.wasm"
    req = urllib.request.Request(wasm, method="HEAD", headers={"Accept-Encoding": "gzip"})
    with urllib.request.urlopen(req, timeout=60) as r:
        etag = r.headers.get("ETag", "")
    req = urllib.request.Request(wasm, method="HEAD",
                                 headers={"Accept-Encoding": "gzip", "If-None-Match": etag})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            status = r.status
    except urllib.error.HTTPError as e:
        status = e.code
    check(bool(etag) and status == 304,
          f"arigl.wasm revalidates: 304 for its compressed ETag {etag or '(none)'} (got {status})")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
