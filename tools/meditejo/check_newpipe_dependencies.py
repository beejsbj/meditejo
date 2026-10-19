#!/usr/bin/env python3
"""Check that assets/licenses/newpipe-runtime-dependencies.json lists exactly
the runtime dependency closure of the pinned NewPipeExtractor, as published.

Walks the POMs over HTTPS (JitPack for com.github.TeamNewPipe, Maven Central
for everything else), following compile and runtime scopes only, and compares
the result with the manifest that drives the in-app licences screen. Never
runs Gradle. Usage: check_newpipe_dependencies.py [manifest.json]
"""
import json
import sys
import urllib.request
import xml.etree.ElementTree as ET

NS = {"m": "http://maven.apache.org/POM/4.0.0"}
JITPACK = "https://jitpack.io"
CENTRAL = "https://repo1.maven.org/maven2"


def pom_url(group, artifact, version):
    base = JITPACK if group == "com.github.TeamNewPipe" else CENTRAL
    return f"{base}/{group.replace('.', '/')}/{artifact}/{version}/{artifact}-{version}.pom"


def fetch_pom(group, artifact, version):
    with urllib.request.urlopen(pom_url(group, artifact, version), timeout=60) as r:
        return ET.fromstring(r.read())


def text(node, path):
    found = node.find(path, NS)
    return found.text.strip() if found is not None and found.text else None


def runtime_deps(root):
    deps = []
    for dep in root.findall("m:dependencies/m:dependency", NS):
        scope = text(dep, "m:scope") or "compile"
        if scope not in ("compile", "runtime") or text(dep, "m:optional") == "true":
            continue
        deps.append(tuple(text(dep, f"m:{k}") for k in ("groupId", "artifactId", "version")))
    return deps


def closure(root_coordinate):
    seen, pending, licences = {}, [tuple(root_coordinate.split(":"))], {}
    while pending:
        coordinate = pending.pop()
        if coordinate in seen:
            continue
        pom = fetch_pom(*coordinate)
        seen[coordinate] = True
        licences[":".join(coordinate)] = [
            text(lic, "m:name") for lic in pom.findall("m:licenses/m:license", NS)
        ]
        pending.extend(runtime_deps(pom))
    return licences


def main():
    manifest_path = sys.argv[1] if len(sys.argv) > 1 else "assets/licenses/newpipe-runtime-dependencies.json"
    with open(manifest_path) as f:
        manifest = json.load(f)
    actual = closure(manifest["extractor"])
    listed = {c for comp in manifest["components"] for c in comp["coordinates"]}
    for coordinate, names in sorted(actual.items()):
        print(f"{coordinate}  POM licence: {', '.join(n for n in names if n) or '(none declared)'}")
    missing, stale = set(actual) - listed, listed - set(actual)
    if missing or stale:
        print(f"Not in the licences manifest: {sorted(missing)}", file=sys.stderr)
        print(f"In the manifest but not a dependency: {sorted(stale)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
