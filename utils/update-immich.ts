#!/usr/bin/env bun

import { YAML } from "bun";
import { join, relative } from "node:path";
import { changelog, downloadFirstText, latestTag } from "./GitHub.ts";
import { assignments, selectAssignment, writeAssignment } from "./NixValue.ts";

const repository = "immich-app/immich";
const versionVariable = "immich-version";
const root = join(import.meta.dir, "..");
const files = {
  nix: join(root, "hosts/nas/docker-services/immich/immich.nix"),
  compose: join(root, "hosts/nas/docker-services/immich/docker-compose.yml"),
  env: join(root, "hosts/nas/docker-services/immich/.env"),
};
const usage = `Usage: update-immich.ts [--dry-run|--apply] [--force]

Updates Immich docker-compose image pins and immich-version in immich.nix.
Apply is the default; pass --dry-run to preview changes without writing.
Pass --force to continue even when potential breaking changes are detected.`;

type Images = Map<string, string>;
type ImageChange = readonly [service: string, oldImage: string, newImage: string];
type YamlObject = Record<string, unknown>;

interface Options { apply: boolean; force: boolean }

async function main(): Promise<void> {
  const { apply, force } = parseArguments(process.argv.slice(2));
  for (const path of Object.values(files)) await requireFile(path);

  const nixText = await Bun.file(files.nix).text();
  const versionAssignment = selectAssignment(versionVariable, assignments(nixText));
  const currentVersion = versionAssignment.value;
  const latestVersion = await latestTag(repository);
  validateNixString(currentVersion);
  validateNixString(latestVersion);

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

  const [assetName, upstreamText] = await downloadCompose(latestVersion);
  console.log(`\nDownloaded upstream ${assetName} for ${latestVersion}.`);
  const localYaml = await readYaml(files.compose);
  const upstreamYaml = parseYaml(assetName, upstreamText);
  const changes = planComposeChanges(composeImages(localYaml), composeImages(upstreamYaml));
  reportComposeChanges(apply, files.compose, changes);

  const envText = await Bun.file(files.env).text();
  const [updatedEnv, envChanged] = removeDuplicatedEnvVersion(envText);
  reportEnvMigration(apply, files.env, envChanged);

  if (apply) {
    if (changes.length) await Bun.write(files.compose, stringifyYaml(replaceImages(localYaml, changes)));
    if (envChanged) await Bun.write(files.env, updatedEnv);
  }
  await writeAssignment(apply, files.nix, nixText, versionAssignment, latestVersion);
}

function parseArguments(commandLineArguments: readonly string[]): Options {
  if (commandLineArguments.some((argument): boolean => argument === "-h" || argument === "--help")) {
    console.log(usage);
    process.exit(0);
  }
  const known = new Set(["--apply", "--dry-run", "--force"]);
  const unknown = commandLineArguments.filter((argument): boolean => !known.has(argument));
  if (unknown.length) fail(`Error: unknown arguments: ${unknown.join(" ")}\n${usage}`);
  if (commandLineArguments.includes("--apply") && commandLineArguments.includes("--dry-run"))
    fail(`Error: --apply and --dry-run are mutually exclusive\n${usage}`);
  return { apply: !commandLineArguments.includes("--dry-run"), force: commandLineArguments.includes("--force") };
}

async function requireFile(path: string): Promise<void> {
  if (!await Bun.file(path).exists()) fail(`Error: required file does not exist: ${path}`);
}

function validateNixString(value: string): void {
  if (!value) fail("Error: version must not be empty");
  if (/["\\\n\r]/.test(value))
    fail(`Error: version contains characters this script will not quote safely: ${JSON.stringify(value)}`);
}

function downloadCompose(tag: string): Promise<[string, string]> {
  return downloadFirstText(["docker-compose.yml", "docker-compose.yaml"].map((name): [string, string] =>
    [name, `https://github.com/${repository}/releases/download/${tag}/${name}`]));
}

async function readYaml(path: string): Promise<unknown> { return parseYaml(path, await Bun.file(path).text()); }

function parseYaml(path: string, text: string): unknown {
  try { return YAML.parse(text) as unknown; }
  catch (error) { return fail(`Error: failed to parse YAML ${path}: ${errorMessage(error)}`); }
}

function stringifyYaml(value: unknown): string {
  const text = YAML.stringify(value, null, 2).replace(/: $/gm, ":");
  return text.endsWith("\n") ? text : `${text}\n`;
}

function composeImages(value: unknown): Images {
  const images: Images = new Map();
  const services = asObject(asObject(value)?.services);
  for (const [name, service] of Object.entries(services ?? {})) {
    const image = asObject(service)?.image;
    if (typeof image === "string") images.set(name, image);
  }
  return images;
}

function planComposeChanges(local: Images, upstream: Images): ImageChange[] {
  const localNames = [...local.keys()].sort(), upstreamNames = [...upstream.keys()].sort();
  if (!upstream.size) fail("Error: no image entries found in upstream Immich compose file");
  if (!local.size) fail("Error: no image entries found in local Immich compose file");
  refuseMissing("upstream compose contains image services missing locally", upstreamNames, local);
  refuseMissing("local compose contains image services missing upstream", localNames, upstream);

  const changes: ImageChange[] = [];
  for (const name of localNames) {
    const oldImage = local.get(name)!, newImage = upstream.get(name)!;
    if (oldImage !== newImage) changes.push([name, oldImage, newImage]);
  }
  return changes;
}

function refuseMissing(message: string, names: readonly string[], target: Images): void {
  const missing = names.filter((name): boolean => !target.has(name));
  if (missing.length) fail(`Error: ${message}: ${missing.join(", ")}. Refusing to silently add/remove services; review Immich compose changes manually.`);
}

function replaceImages(yaml: unknown, changes: readonly ImageChange[]): unknown {
  const services = asObject(asObject(yaml)?.services);
  for (const [name, , newImage] of changes) {
    const service = asObject(services?.[name]);
    if (service) service.image = newImage;
  }
  return yaml;
}

function reportComposeChanges(apply: boolean, composeFile: string, changes: readonly ImageChange[]): void {
  if (!changes.length) {
    console.log(`${composeFile}: compose image pins are already aligned with upstream.`);
    return;
  }
  console.log("\nCompose image changes:");
  for (const [name, oldImage, newImage] of changes) console.log(`- ${name}: ${oldImage} -> ${newImage}`);
  console.log(`${apply ? "Updated" : "Would update"} ${composeFile}: ${changes.length} image pin(s)`);
}

function removeDuplicatedEnvVersion(text: string): [string, boolean] {
  let changed = false;
  const updated = text.split(/\r?\n/).map((line): string => {
    if (!line.trim().startsWith("IMMICH_VERSION=")) return line;
    changed = true;
    return "# IMMICH_VERSION is managed by immich-version in immich.nix.";
  });
  return [changed ? updated.join("\n") : text, changed];
}

function reportEnvMigration(apply: boolean, envFile: string, changed: boolean): void {
  console.log(changed
    ? `${apply ? "Updated" : "Would update"} ${envFile}: remove duplicated IMMICH_VERSION from env file`
    : `${envFile}: no duplicated IMMICH_VERSION entry found.`);
}

function gateBreakingChanges(force: boolean, releaseNotes: string): void {
  const suspiciousSections = splitMarkdownSections(releaseNotes).filter((section): boolean => suspicious(section));
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

function suspicious(section: string): boolean {
  const lower = section.toLowerCase().trim().split(/\s+/).join(" ");
  return !nonBreakingPhrases.some((phrase): boolean => lower.includes(phrase))
    && breakingKeywords.some((keyword): boolean => lower.includes(keyword));
}

const breakingKeywords = [
  "breaking change", "breaking changes", "breaking:", "migration guide", "manual migration", "manual action",
  "manual step", "manual intervention", "action required", "required action", "requires manual", "database migration",
  "storage template migration", "removed support", "remove support", "before upgrading", "after upgrading", "must update",
  "must be updated", "cannot upgrade", "migrating from", "migrate from",
];
const nonBreakingPhrases = [
  "no breaking changes", "no breaking change", "without breaking changes", "does not contain breaking changes",
  "does not include breaking changes", "nothing is currently planned that requires user intervention",
  "nothing currently planned that requires user intervention",
];

function splitMarkdownSections(markdown: string): string[] {
  const sections: string[] = [];
  for (const line of markdown.split(/\r?\n/)) {
    if (!sections.length || line.trimStart().startsWith("#")) sections.push(line);
    else sections[sections.length - 1] += `\n${line}`;
  }
  return sections;
}

function asObject(value: unknown): YamlObject | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as YamlObject : undefined;
}
function errorMessage(error: unknown): string { return error instanceof Error ? error.message : String(error); }
function fail(message: string): never { throw new Error(message); }

main().catch((error: unknown): void => {
  console.error(errorMessage(error));
  process.exitCode = 1;
});
