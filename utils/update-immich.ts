#!/usr/bin/env bun

import { YAML } from "bun";
import { join, relative } from "node:path";
import { changelog, downloadFirstText, latestTag } from "./GitHub.ts";
import { assignments, selectAssignment, writeAssignment } from "./NixValue.ts";

const repository = "immich-app/immich";
const versionVariable = "immich-version";
const root = join(import.meta.dir, "..");
const directory = join(root, "hosts/nas/docker-services/immich");
const files = {
  nix: join(directory, "immich.nix"),
  compose: join(directory, "docker-compose.yml"),
  env: join(directory, ".env"),
};
const usage = `Usage: update-immich.ts [--dry-run|--apply] [--force]

Updates Immich docker-compose image pins and immich-version in immich.nix.
Apply is the default; pass --dry-run to preview changes without writing.
Pass --force to continue even when potential breaking changes are detected.`;

type Images = Map<string, string>;
type ImageChange = readonly [service: string, oldImage: string, newImage: string];

async function main(): Promise<void> {
  const { apply, force } = parseArguments(process.argv.slice(2));
  for (const path of Object.values(files)) {
    if (!await Bun.file(path).exists()) fail(`Error: required file does not exist: ${path}`);
  }

  const nixText = await Bun.file(files.nix).text();
  const versionAssignment = selectAssignment(versionVariable, assignments(nixText));
  const currentVersion = versionAssignment.value;
  const latestVersion = await latestTag(repository);
  for (const version of [currentVersion, latestVersion]) {
    if (!version) fail("Error: version must not be empty");
    if (/["\\\n\r]/.test(version))
      fail(`Error: version contains characters this script will not quote safely: ${JSON.stringify(version)}`);
  }

  console.log([
    "Service: Immich", `GitHub repo: ${repository}`, `Version variable: ${versionVariable}`,
    `Nix file: ${relative(root, files.nix)}`, `Compose file: ${relative(root, files.compose)}`,
    `Current version: ${currentVersion}`, `Latest release: ${latestVersion}`, `Mode: ${apply ? "apply" : "dry-run"}`,
  ].join("\n"));

  if (currentVersion !== latestVersion) {
    const releaseNotes = await changelog(repository, currentVersion, latestVersion);
    console.log(`\nChangelog:\n${releaseNotes}`);
    gateBreakingChanges(force, releaseNotes);
  }

  const [assetName, upstreamText] = await downloadFirstText(
    ["docker-compose.yml", "docker-compose.yaml"].map(name =>
      [name, `https://github.com/${repository}/releases/download/${latestVersion}/${name}`]));
  console.log(`\nDownloaded upstream ${assetName} for ${latestVersion}.`);
  const localYaml = parseYaml(files.compose, await Bun.file(files.compose).text());
  const upstreamYaml = parseYaml(assetName, upstreamText);
  const changes = planComposeChanges(composeImages(localYaml), composeImages(upstreamYaml));
  if (changes.length) {
    console.log("\nCompose image changes:");
    for (const [name, oldImage, newImage] of changes) console.log(`- ${name}: ${oldImage} -> ${newImage}`);
    console.log(`${apply ? "Updated" : "Would update"} ${files.compose}: ${changes.length} image pin(s)`);
  } else console.log(`${files.compose}: compose image pins are already aligned with upstream.`);

  const envText = await Bun.file(files.env).text();
  const updatedEnv = removeDuplicatedEnvVersion(envText);
  const envChanged = updatedEnv !== envText;
  console.log(envChanged
    ? `${apply ? "Updated" : "Would update"} ${files.env}: remove duplicated IMMICH_VERSION from env file`
    : `${files.env}: no duplicated IMMICH_VERSION entry found.`);

  if (apply) {
    if (changes.length) await Bun.write(files.compose, updatedCompose(localYaml, changes));
    if (envChanged) await Bun.write(files.env, updatedEnv);
  }
  await writeAssignment(apply, files.nix, nixText, versionAssignment, latestVersion);
}

function parseArguments(args: readonly string[]) {
  if (args.some(argument => argument === "-h" || argument === "--help")) {
    console.log(usage);
    process.exit(0);
  }
  const unknown = args.filter(argument => !["--apply", "--dry-run", "--force"].includes(argument));
  if (unknown.length) fail(`Error: unknown arguments: ${unknown.join(" ")}\n${usage}`);
  if (args.includes("--apply") && args.includes("--dry-run"))
    fail(`Error: --apply and --dry-run are mutually exclusive\n${usage}`);
  return { apply: !args.includes("--dry-run"), force: args.includes("--force") };
}

function parseYaml(path: string, text: string): unknown {
  try { return YAML.parse(text); }
  catch (error) { fail(`Error: failed to parse YAML ${path}: ${errorMessage(error)}`); }
}

function composeImages(value: unknown): Images {
  const services = asObject(asObject(value)?.services);
  return new Map(Object.entries(services ?? {}).flatMap(([name, service]) => {
    const image = asObject(service)?.image;
    return typeof image === "string" ? [[name, image]] : [];
  }));
}

function planComposeChanges(local: Images, upstream: Images): ImageChange[] {
  const localNames = [...local.keys()].sort(), upstreamNames = [...upstream.keys()].sort();
  if (!upstream.size) fail("Error: no image entries found in upstream Immich compose file");
  if (!local.size) fail("Error: no image entries found in local Immich compose file");
  refuseMissing("upstream compose contains image services missing locally", upstreamNames, local);
  refuseMissing("local compose contains image services missing upstream", localNames, upstream);

  return localNames.flatMap((name): ImageChange[] => {
    const oldImage = local.get(name)!, newImage = upstream.get(name)!;
    return oldImage === newImage ? [] : [[name, oldImage, newImage]];
  });
}

function refuseMissing(message: string, names: readonly string[], target: Images): void {
  const missing = names.filter(name => !target.has(name));
  if (missing.length) fail(`Error: ${message}: ${missing.join(", ")}. Refusing to silently add/remove services; review Immich compose changes manually.`);
}

function updatedCompose(yaml: unknown, changes: readonly ImageChange[]): string {
  const services = asObject(asObject(yaml)?.services);
  for (const [name, , newImage] of changes) {
    const service = asObject(services?.[name]);
    if (service) service.image = newImage;
  }
  return YAML.stringify(yaml, null, 2).replace(/: $/gm, ":").replace(/\n?$/, "\n");
}

function removeDuplicatedEnvVersion(text: string): string {
  const lines = text.split(/\r?\n/);
  const updated = lines.map(line => line.trim().startsWith("IMMICH_VERSION=")
    ? "# IMMICH_VERSION is managed by immich-version in immich.nix." : line);
  return updated.some((line, index) => line !== lines[index]) ? updated.join("\n") : text;
}

function gateBreakingChanges(force: boolean, releaseNotes: string): void {
  // Normalize line endings, then split before optionally indented headings.
  const suspiciousSections = releaseNotes.replace(/\r\n/g, "\n").split(/\n(?=[^\S\n]*#)/).filter(section => {
    const lower = section.toLowerCase().trim().replace(/\s+/g, " ");
    return !nonBreakingPhrases.some(phrase => lower.includes(phrase))
      && breakingKeywords.some(keyword => lower.includes(keyword));
  });
  if (!suspiciousSections.length) {
    console.log("\nNo obvious breaking/migration/manual-action sections detected in release notes.");
    return;
  }

  console.log("\nPotential breaking changes or migration/manual-action notes were detected.");
  console.log(force
    ? "Continuing anyway (--force). Review the excerpts below.\n"
    : "No files were written. Review the excerpts below before applying the update.\n");
  for (const [index, section] of suspiciousSections.slice(0, 10).entries()) {
    console.log(`--- Potential issue ${index + 1} ---`);
    console.log(section.split("\n").slice(0, 80).join("\n").trim());
  }
  if (suspiciousSections.length > 10)
    console.log(`\n... ${suspiciousSections.length - 10} additional suspicious section(s) omitted.`);
  if (!force) process.exit(1);
}

const breakingKeywords = [
  "breaking change", "breaking:", "migration guide", "manual migration", "manual action",
  "manual step", "manual intervention", "action required", "required action", "requires manual", "database migration",
  "storage template migration", "removed support", "remove support", "before upgrading", "after upgrading", "must update",
  "must be updated", "cannot upgrade", "migrating from", "migrate from",
];
const nonBreakingPhrases = [
  "no breaking change", "without breaking changes", "does not contain breaking changes",
  "does not include breaking changes", "nothing is currently planned that requires user intervention",
  "nothing currently planned that requires user intervention",
];

function asObject(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : undefined;
}
function errorMessage(error: unknown): string { return error instanceof Error ? error.message : String(error); }
function fail(message: string): never { throw new Error(message); }

main().catch((error: unknown): void => {
  console.error(errorMessage(error));
  process.exitCode = 1;
});
