#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3 python3Packages.requests
"""Print the latest stable GitHub release field for a repository."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from urllib.parse import urlparse

import requests

API_BASE_URL = "https://api.github.com"
DEFAULT_TIMEOUT_SECONDS = 30
DEFAULT_FIELD = "tag_name"
FIELD_CHOICES = ("tag_name", "name", "html_url", "published_at", "body", "json")
UNSTABLE_RELEASE_PATTERN = re.compile(
    r"\b(alpha|alfa|beta|rc|pre[- ]?release|preview|nightly|dev|canary)\b",
    re.IGNORECASE,
)
Release = dict[str, object]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Fetch the latest stable GitHub release and print a selected field."
        )
    )
    parser.add_argument(
        "repo",
        help="GitHub repo as owner/name or full URL, e.g. immich-app/immich",
    )
    parser.add_argument(
        "--field",
        choices=FIELD_CHOICES,
        default=DEFAULT_FIELD,
        help="Release field to print. Defaults to tag_name.",
    )
    return parser.parse_args()


def normalize_repo(repo: str) -> str:
    repo = repo.strip()
    if "://" not in repo:
        parts = [part for part in repo.strip("/").split("/") if part]
        if len(parts) != 2:
            raise ValueError(f"Invalid repository reference: {repo!r}")
        return f"{parts[0]}/{parts[1].removesuffix('.git')}"

    parsed = urlparse(repo)
    if parsed.netloc not in {"github.com", "www.github.com"}:
        raise ValueError(f"Expected a github.com URL, got {repo!r}")

    parts = [part for part in parsed.path.strip("/").split("/") if part]
    if len(parts) < 2:
        raise ValueError(f"Invalid GitHub repository URL: {repo!r}")

    return f"{parts[0]}/{parts[1].removesuffix('.git')}"


def github_session(token: str | None) -> requests.Session:
    session = requests.Session()
    session.headers.update(
        {
            "Accept": "application/vnd.github+json",
            "User-Agent": "github-latest-release-script",
            "X-GitHub-Api-Version": "2022-11-28",
        }
    )
    if token:
        session.headers["Authorization"] = f"Bearer {token}"
    return session


def fetch_latest_release(repo: str, token: str | None) -> Release:
    next_url = f"{API_BASE_URL}/repos/{repo}/releases?per_page=100"

    with github_session(token) as session:
        while next_url:
            response = session.get(next_url, timeout=DEFAULT_TIMEOUT_SECONDS)
            response.raise_for_status()
            payload = response.json()

            if not isinstance(payload, list):
                raise RuntimeError(f"Unexpected GitHub API response for {repo}")

            for release in payload:
                if isinstance(release, dict) and is_stable_release(release):
                    return release

            next_url = response.links.get("next", {}).get("url")

    raise ValueError(f"No stable GitHub releases found for {repo}")


def is_stable_release(release: Release) -> bool:
    if release.get("draft") or release.get("prerelease"):
        return False

    for field_name in ("tag_name", "name"):
        value = release.get(field_name)
        if isinstance(value, str) and UNSTABLE_RELEASE_PATTERN.search(value):
            return False

    return True


def render_field(release: Release, field: str) -> str:
    if field == "json":
        return json.dumps(release, indent=2, sort_keys=True)

    value = release.get(field)
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    return str(value)


def main() -> int:
    args = parse_args()

    try:
        repo = normalize_repo(args.repo)
        token = os.getenv("GITHUB_TOKEN") or os.getenv("GH_TOKEN")
        release = fetch_latest_release(repo, token)
        sys.stdout.write(f"{render_field(release, args.field)}\n")
    except ValueError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 2
    except requests.HTTPError as error:
        response = error.response
        status_code = response.status_code if response is not None else "unknown"
        reason = response.reason if response is not None else str(error)
        details = response.text.strip() if response is not None else ""
        if details:
            print(
                f"GitHub API error: {status_code} {reason}: {details}",
                file=sys.stderr,
            )
        else:
            print(f"GitHub API error: {status_code} {reason}", file=sys.stderr)
        return 1
    except requests.RequestException as error:
        print(f"Network error: {error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
