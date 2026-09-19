#!/usr/bin/env bun

import { YAML } from "bun";
import { join } from "node:path";
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
  const tag = await latestTag(repository);
  const compose = YAML.parse(await downloadText(
    `https://raw.githubusercontent.com/${repository}/${encodeURIComponent(tag)}/docker/compose/docker-compose.sqlite-tika.yml`,
  )) as { services: Record<string, { image: string }> };
  const path = join(import.meta.dir, "../hosts/nas/docker-services/paperless.nix");
  const original = await Bun.file(path).text();
  const lines = original.split("\n");
  const all = assignments(original);

  for (const [service, variable, image] of [
    ["broker", "valkey-version", "docker.io/valkey/valkey"],
    ["webserver", "paperless-version", "ghcr.io/paperless-ngx/paperless-ngx"],
    ["tika", "tika-version", "docker.io/apache/tika"],
    ["gotenberg", "gotenberg-version", "docker.io/gotenberg/gotenberg"],
  ] as const) {
    const upstream = compose.services?.[service]?.image;
    if (typeof upstream !== "string" || !upstream.startsWith(`${image}:`))
      throw new Error(`Unexpected upstream image for ${service}: ${upstream}`);
    const version = service === "webserver" ? tag : upstream.slice(image.length + 1);
    if (!/^[\w][\w.-]{0,127}$/.test(version)) throw new Error(`Invalid image tag: ${version}`);
    const assignment = selectAssignment(variable, all);
    lines[assignment.lineNumber] = `${assignment.indent}${variable} = "${version}";${assignment.trailing}`;
    console.log(`${variable}: ${assignment.value} -> ${version}`);
  }

  const updated = lines.join("\n");
  if (updated === original) return console.log("Already up to date.");
  if (apply) await Bun.write(path, updated);
  console.log(`${apply ? "Updated" : "Would update"} ${path}`);
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
