#!/usr/bin/env bun

import { YAML } from "bun";
import { join, relative } from "node:path";
import { downloadText, latestTag } from "./GitHub.ts";
import { assignments, selectAssignment } from "./NixValue.ts";

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const usage = "Usage: update-paperless.ts [--dry-run|--apply] (default: apply)";
  if (args.includes("--help") || args.includes("-h")) return console.log(usage);
  if (args.some(arg => !["--dry-run", "--apply"].includes(arg)) ||
      (args.includes("--dry-run") && args.includes("--apply"))) throw new Error(usage);
  const apply = !args.includes("--dry-run");
  const repository = "paperless-ngx/paperless-ngx";
  const [githubTag, paperlessGptVersion] = await Promise.all([
    latestTag(repository), latestTag("icereed/paperless-gpt"),
  ]);
  const imageTag = await fetch(
    `https://hub.docker.com/v2/repositories/icereed/paperless-gpt/tags/${encodeURIComponent(paperlessGptVersion)}`,
    { signal: AbortSignal.timeout(30_000) },
  );
  if (!imageTag.ok) throw new Error(`paperless-gpt image tag ${paperlessGptVersion}: ${imageTag.status} ${imageTag.statusText}`);
  const paperlessVersion = githubTag.replace(/^v/, "");
  const compose = YAML.parse(await downloadText(
    `https://raw.githubusercontent.com/${repository}/${encodeURIComponent(githubTag)}/docker/compose/docker-compose.sqlite-tika.yml`,
  )) as { services: Record<string, { image: string }> };
  const root = join(import.meta.dir, "..");
  const path = join(root, "hosts/nas/docker-services/paperless.nix");
  const original = await Bun.file(path).text();
  const lines = original.split("\n");
  const all = assignments(original);
  const changes: string[] = [];

  function setVersion(variable: string, version: string): void {
    if (!/^[\w][\w.-]{0,127}$/.test(version)) throw new Error(`Invalid image tag: ${version}`);
    const assignment = selectAssignment(variable, all);
    lines[assignment.lineNumber] = `${assignment.indent}${variable} = "${version}";${assignment.trailing}`;
    console.log(`${variable}: ${assignment.value} -> ${version}`);
    if (assignment.value !== version)
      changes.push(`${variable.replace(/-version$/, "")}: ${assignment.value} -> ${version}`);
  }

  for (const [service, variable, image] of [
    ["broker", "valkey-version", "docker.io/valkey/valkey"],
    ["webserver", "paperless-version", "ghcr.io/paperless-ngx/paperless-ngx"],
    ["tika", "tika-version", "docker.io/apache/tika"],
    ["gotenberg", "gotenberg-version", "docker.io/gotenberg/gotenberg"],
  ] as const) {
    const upstream = compose.services?.[service]?.image;
    if (typeof upstream !== "string" || !upstream.startsWith(`${image}:`))
      throw new Error(`Unexpected upstream image for ${service}: ${upstream}`);
    const version = service === "webserver" ? paperlessVersion : upstream.slice(image.length + 1);
    setVersion(variable, version);
  }
  setVersion("paperless-gpt-version", paperlessGptVersion);

  const updated = lines.join("\n");
  if (updated === original) return console.log("Already up to date.");
  if (apply) {
    await Bun.write(path, updated);
    await commitUpdate(root, `update paperless services\n\n${changes.join("\n")}`, [relative(root, path)]);
  }
  console.log(`${apply ? "Updated" : "Would update"} ${path}`);
}

async function commitUpdate(
  root: string, message: string, paths: readonly string[],
): Promise<void> {
  console.log(`Committing: ${message}`);
  const child = Bun.spawn(["jj", "commit", "-m", message, ...paths], {
    cwd: root,
    stdout: "inherit",
    stderr: "inherit",
  });
  const exitCode = await child.exited;
  if (exitCode !== 0) throw new Error(`Error: jj commit failed with exit code ${exitCode}`);
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
