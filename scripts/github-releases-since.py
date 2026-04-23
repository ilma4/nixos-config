#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3 python3Packages.requests
"""Export GitHub release notes newer than a given release tag to Markdown."""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

import requests

API_BASE_URL = "https://api.github.com"
UNSTABLE_RELEASE_PATTERN = re.compile(
    r"\b(alpha|alfa|beta|pre[- ]?release)\b", re.IGNORECASE
)

Release = dict[str, object]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Fetch all GitHub releases newer than a given release tag and write "
            "their descriptions to a Markdown file."
        )
    )
    parser.add_argument(
        "repo",
        help="GitHub repo as owner/name or full URL, e.g. immich-app/immich",
    )
    parser.add_argument(
        "since_release", help="Release tag to start from, excluded from the output"
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Output Markdown path. Defaults to stdout.",
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
            "User-Agent": "github-releases-since-script",
            "X-GitHub-Api-Version": "2022-11-28",
        }
    )
    if token:
        session.headers["Authorization"] = f"Bearer {token}"
    return session


def fetch_releases_since(
    repo: str, since_release: str, token: str | None
) -> list[Release]:
    releases: list[Release] = []
    next_url = f"{API_BASE_URL}/repos/{repo}/releases?per_page=100"

    with github_session(token) as session:
        while next_url:
            response = session.get(next_url)
            response.raise_for_status()

            payload = response.json()
            if not isinstance(payload, list):
                raise RuntimeError(f"Unexpected GitHub API response for {repo}")

            for release in payload:
                if not isinstance(release, dict):
                    continue
                if release.get("tag_name") == since_release:
                    return releases
                if release.get("draft") or is_unstable_release(release):
                    continue
                releases.append(release)

            next_url = response.links.get("next", {}).get("url")

    raise ValueError(
        f"Release tag {since_release!r} was not found in GitHub releases for {repo}"
    )


def release_sort_key(release: Release) -> str:
    published_at = release.get("published_at")
    created_at = release.get("created_at")
    if isinstance(published_at, str) and published_at:
        return published_at
    if isinstance(created_at, str) and created_at:
        return created_at
    return ""


def is_unstable_release(release: Release) -> bool:
    if release.get("prerelease"):
        return True

    for field_name in ("tag_name", "name"):
        value = release.get(field_name)
        if isinstance(value, str) and UNSTABLE_RELEASE_PATTERN.search(value):
            return True

    return False


def release_title(release: Release) -> str:
    name = release.get("name")
    tag_name = release.get("tag_name")
    if isinstance(name, str) and name.strip():
        return name.strip()
    if isinstance(tag_name, str) and tag_name.strip():
        return tag_name.strip()
    return "Unnamed release"


def release_body(release: Release) -> str:
    body = release.get("body")
    if not isinstance(body, str) or not body.strip():
        return "_No description provided._"

    body = normalize_markdown_headings(body.strip())
    body = strip_duplicate_title(body, release)
    return body or "_No description provided._"


def normalize_markdown_headings(body: str) -> str:
    normalized_lines: list[str] = []
    for line in body.splitlines():
        match = re.match(r"^(#{1,5})(\s+.*)$", line)
        if not match:
            normalized_lines.append(line)
            continue

        heading_level = min(len(match.group(1)) + 2, 6)
        normalized_lines.append(f"{'#' * heading_level}{match.group(2)}")

    return "\n".join(normalized_lines)


def strip_duplicate_title(body: str, release: Release) -> str:
    lines = body.splitlines()
    if not lines:
        return body

    first_line_match = re.match(r"^#{1,6}\s+(.*)$", lines[0].strip())
    if not first_line_match:
        return body

    candidate_titles = {
        release_title(release).strip(),
        str(release.get("tag_name", "")).strip(),
    }
    if first_line_match.group(1).strip() not in candidate_titles:
        return body

    remaining_lines = lines[1:]
    while remaining_lines and not remaining_lines[0].strip():
        remaining_lines = remaining_lines[1:]
    return "\n".join(remaining_lines).strip()


def render_markdown(repo: str, since_release: str, releases: list[Release]) -> str:
    sorted_releases = sorted(releases, key=release_sort_key)
    lines = [
        f"# Releases for `{repo}` since `{since_release}`",
        "",
        f"Found {len(sorted_releases)} release(s) newer than `{since_release}`.",
        "",
    ]

    if not sorted_releases:
        lines.append("_No newer releases were found._")
        lines.append("")
        return "\n".join(lines)

    for release in sorted_releases:
        tag_name = release.get("tag_name", "unknown")
        html_url = release.get("html_url", "")
        published_at = (
            release.get("published_at") or release.get("created_at") or "unknown"
        )
        prerelease = release.get("prerelease")

        lines.append(f"## {release_title(release)}")
        lines.append("")
        lines.append(f"- Tag: `{tag_name}`")
        lines.append(f"- Published: `{published_at}`")
        if html_url:
            lines.append(f"- URL: {html_url}")
        if prerelease:
            lines.append("- Type: prerelease")
        lines.append("")
        lines.append(release_body(release))
        lines.append("")

    return "\n".join(lines)
def main() -> int:
    args = parse_args()

    try:
        repo = normalize_repo(args.repo)
        token = os.getenv("GITHUB_TOKEN") or os.getenv("GH_TOKEN")
        releases = fetch_releases_since(repo, args.since_release, token)
        markdown = render_markdown(repo, args.since_release, releases)
        if args.output is None:
            sys.stdout.write(markdown)
        else:
            args.output.write_text(markdown, encoding="utf-8")
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
    except OSError as error:
        print(f"Filesystem error: {error}", file=sys.stderr)
        return 1

    if args.output is not None:
        print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
