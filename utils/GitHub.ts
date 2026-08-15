type TagPredicate = (tag: string) => boolean;
type Download = readonly [label: string, url: string];

interface Release {
  tag_name?: string | null; name?: string | null; html_url?: string | null;
  published_at?: string | null; created_at?: string | null; body?: string | null;
  draft?: boolean | null; prerelease?: boolean | null;
}

const unstableLabels = new Set(["alpha", "alfa", "beta", "rc", "preview", "nightly", "dev", "canary", "prerelease"]);

export async function latestTag(repository: string): Promise<string> {
  const release = await fetchJson<Release>(githubApiUrl(repository, "/releases/latest"));
  return tagOf(release) ?? fail(`Error: latest GitHub release for ${repository} has no tag_name`);
}

export async function latestTagWhere(repository: string, keepTag: TagPredicate): Promise<string> {
  const tags = tagsOf(await stableReleasesWhere(repository, keepTag));
  return tags.length ? highestVersion(tags) : fail(`Error: no stable GitHub release for ${repository} matched the requested version`);
}

export async function latestTagAfterWhere(repository: string, currentTag: string, keepTag: TagPredicate): Promise<string> {
  const tags = tagsOf((await releasesAfter(repository, currentTag)).filter((release): boolean => {
    const tag = tagOf(release);
    return stable(release) && tag !== undefined && keepTag(tag) && compareVersions(tag, currentTag) > 0;
  }));
  return tags.length ? highestVersion(tags) : currentTag;
}

export async function changelog(repository: string, fromTag: string, toTag: string): Promise<string> {
  return changelogWhere(repository, fromTag, toTag, (_tag: string): boolean => true);
}

export async function changelogWhere(repository: string, fromTag: string, toTag: string, keepTag: TagPredicate): Promise<string> {
  return renderChangelog(repository, fromTag, toTag, await changelogReleasesWhere(repository, fromTag, toTag, keepTag));
}

export async function downloadText(url: string): Promise<string> { return (await request(url)).text(); }

export async function downloadFirstText(downloads: readonly Download[]): Promise<[string, string]> {
  const failures: string[] = [];
  for (const [label, url] of downloads) {
    try { return [label, await downloadText(url)]; }
    catch (error) { failures.push(`- ${label} (${url}): ${errorMessage(error)}`); }
  }
  return fail(["Error: all GitHub downloads failed:", ...failures].join("\n"));
}

async function changelogReleasesWhere(repository: string, fromTag: string, toTag: string, keepTag: TagPredicate): Promise<Release[]> {
  if (fromTag === toTag) return [];
  if (compareVersions(toTag, fromTag) <= 0)
    fail(`Error: target release ${JSON.stringify(toTag)} is not newer than current release ${JSON.stringify(fromTag)} for ${repository}`);

  const releases = await releasesAfter(repository, fromTag);
  if (!releases.some((release): boolean => tagOf(release) === toTag))
    fail(`Error: Release tag ${JSON.stringify(toTag)} was not found after ${JSON.stringify(fromTag)} in GitHub releases for ${repository}`);

  return releases.filter((release): boolean => {
    const tag = tagOf(release);
    return stable(release) && tag !== undefined && keepTag(tag)
      && compareVersions(tag, fromTag) > 0 && compareVersions(tag, toTag) <= 0;
  });
}

async function releasesAfter(repository: string, currentTag: string): Promise<Release[]> {
  const newerReleases: Release[] = [];
  for (let page = 1; ; page++) {
    const releases = await fetchJson<Release[]>(githubApiUrl(repository, `/releases?per_page=100&page=${page}`));
    if (!releases.length)
      fail(`Error: Release tag ${JSON.stringify(currentTag)} was not found in GitHub releases for ${repository}`);
    for (const release of releases) {
      if (tagOf(release) === currentTag) return newerReleases;
      newerReleases.push(release);
    }
  }
}

async function allReleases(repository: string): Promise<Release[]> {
  const all: Release[] = [];
  for (let page = 1; ; page++) {
    const releases = await fetchJson<Release[]>(githubApiUrl(repository, `/releases?per_page=100&page=${page}`));
    if (!releases.length) return all;
    all.push(...releases);
  }
}

async function stableReleasesWhere(repository: string, keepTag: TagPredicate): Promise<Release[]> {
  return (await allReleases(repository)).filter((release): boolean => {
    const tag = tagOf(release);
    return stable(release) && tag !== undefined && keepTag(tag);
  });
}

async function fetchJson<Value>(url: string): Promise<Value> {
  const text = await downloadText(url);
  try { return JSON.parse(text) as Value; }
  catch (error) { return fail(`Error: failed to decode GitHub API response: ${errorMessage(error)}`); }
}

async function request(url: string): Promise<Response> {
  const token = [process.env.GITHUB_TOKEN, process.env.GH_TOKEN].find((value): boolean => Boolean(value?.trim()));
  const headers: Record<string, string> = {
    Accept: "application/vnd.github+json", "User-Agent": "nixos-config-update-tools", "X-GitHub-Api-Version": "2022-11-28",
  };
  if (token) headers.Authorization = `Bearer ${token}`;
  try {
    const response = await fetch(url, { headers, signal: AbortSignal.timeout(30_000) });
    if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
    return response;
  } catch (error) { return fail(`GitHub API/network error: ${errorMessage(error)}`); }
}

function githubApiUrl(repository: string, path: string): string { return `https://api.github.com/repos/${repository}${path}`; }

function tagsOf(releases: readonly Release[]): string[] {
  const tags: string[] = [];
  for (const release of releases) {
    const tag = tagOf(release);
    if (tag !== undefined) tags.push(tag);
  }
  return tags;
}

function tagOf(release: Release): string | undefined { return nonEmpty(release.tag_name); }

function highestVersion(tags: readonly string[]): string {
  return tags.reduce((highest, tag): string => compareVersions(tag, highest) >= 0 ? tag : highest);
}

function compareVersions(leftTag: string, rightTag: string): number {
  const left = versionKey(leftTag), right = versionKey(rightTag);
  for (let index = 0; index < Math.min(left.length, right.length); index++) {
    const difference = left[index]! - right[index]!;
    if (difference) return difference;
  }
  return left.length - right.length;
}

function versionKey(tag: string): number[] { return [...tag.matchAll(/\d+/g)].map((match): number => Number(match[0])); }

function stable(release: Release): boolean {
  return !release.draft && !release.prerelease
    && [release.tag_name, release.name].every((label): boolean => label == null || !unstable(label));
}

function unstable(label: string): boolean {
  const lower = label.toLowerCase();
  return lower.includes("pre-release") || lower.includes("pre release")
    || lower.split(/[^a-z0-9]+/).some((token): boolean => unstableLabels.has(token));
}

function renderChangelog(repository: string, fromTag: string, toTag: string, releases: readonly Release[]): string {
  const sorted = [...releases].sort((left, right): number => compareText(releaseDate(left) ?? "", releaseDate(right) ?? ""));
  const lines = [
    `# Releases for \`${repository}\` since \`${fromTag}\` through \`${toTag}\``, "",
    `Found ${sorted.length} stable release(s) newer than \`${fromTag}\` through \`${toTag}\`.`, "",
    ...(sorted.length ? sorted.flatMap(renderRelease) : ["_No newer releases were found._", ""]),
  ];
  return `${lines.join("\n")}\n`;
}

function renderRelease(release: Release): string[] {
  const name = nonEmpty(release.name) ?? tagOf(release) ?? "Unnamed release";
  const url = nonEmpty(release.html_url), body = nonEmpty(release.body);
  return [
    `## ${name}`, "", `- Tag: \`${release.tag_name ?? "unknown"}\``,
    `- Published: \`${releaseDate(release) ?? "unknown"}\``,
    ...(url ? [`- URL: ${url}`] : []), "", body?.trim() ?? "_No description provided._", "",
  ];
}

function releaseDate(release: Release): string | null | undefined { return release.published_at ?? release.created_at; }
function nonEmpty(value: string | null | undefined): string | undefined { return value?.trim() ? value : undefined; }
function compareText(left: string, right: string): number { return left < right ? -1 : left > right ? 1 : 0; }
function errorMessage(error: unknown): string { return error instanceof Error ? error.message : String(error); }
function fail(message: string): never { throw new Error(message); }
