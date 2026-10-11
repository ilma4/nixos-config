import { afterAll, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, readFileSync, rmSync, statSync, chmodSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { recordBackupStatus } from "../modules/backup/backup";
import { collect, compareSnapshots, selectSnapshots } from "../modules/backup/monitor";

const directory = mkdtempSync(join(tmpdir(), "i4-backup-monitoring-"));
afterAll(() => rmSync(directory, { recursive: true, force: true }));

test("partial status survives failures and restarts, and clears only on exit zero", () => {
  const metrics = { file: join(directory, "backup.prom"), source: "quicksilver" };
  const previousUmask = process.umask(0o077);
  try {
    recordBackupStatus(metrics, 3);
    expect(readFileSync(metrics.file, "utf8")).toContain('backup_partial_unresolved{source="quicksilver"} 1');
    expect(statSync(metrics.file).mode & 0o777).toBe(0o644);
    const restarted = spawnSync(process.execPath, ["-e", `import {recordBackupStatus} from ${JSON.stringify(resolve("modules/backup/backup.ts"))}; recordBackupStatus(${JSON.stringify(metrics)}, 1);`]);
    expect(restarted.status).toBe(0);
    expect(readFileSync(metrics.file, "utf8")).toContain('backup_partial_unresolved{source="quicksilver"} 1');
    recordBackupStatus(metrics, 0);
    expect(readFileSync(metrics.file, "utf8")).toContain('backup_partial_unresolved{source="quicksilver"} 0');
  } finally {
    process.umask(previousUmask);
  }
});

const snapshot = {
  id: "a".repeat(64), time: "2026-10-01T04:00:00Z", tree: "tree",
  hostname: "mac", username: "user", uid: 1000, gid: 1000, paths: ["/home/user"], tags: [],
};
test("copied IDs match; equal counts with different history and rewritten content do not", () => {
  const copy = { ...snapshot, id: "b".repeat(64), original: snapshot.id };
  expect(compareSnapshots([snapshot], [copy])).toEqual([0, 0]);
  expect(compareSnapshots([snapshot], [{ ...copy, original: "c".repeat(64) }])).toEqual([1, 1]);
  expect(compareSnapshots([snapshot], [{ ...copy, tree: "changed" }])).toEqual([1, 1]);
  expect(compareSnapshots([snapshot], [])).toEqual([1, 0]);
  expect(selectSnapshots([snapshot, { ...snapshot, hostname: "other" }], { hostname: "mac", paths: ["/home/user"] })).toEqual([snapshot]);
});

test("collector inspects real copied snapshots, empty repos and retains values on read failure", async () => {
  const passwordFile = join(directory, "password");
  writeFileSync(passwordFile, "temporary-test-password");
  const data = join(directory, "data");
  writeFileSync(data, "backup monitoring integration test");
  const left = join(directory, "left");
  const right = join(directory, "right");
  const restic = (repo: string, ...args: string[]) => {
    const result = spawnSync("restic", ["-r", repo, "--password-file", passwordFile, ...args], { encoding: "utf8" });
    expect(result.status, result.stderr).toBe(0);
    return result.stdout;
  };
  restic(left, "init");
  restic(right, "init", "--copy-chunker-params", "--from-repo", left, "--from-password-file", passwordFile);
  restic(left, "backup", "--host", "mac", data);
  let received = "";
  const server = Bun.serve({ hostname: "127.0.0.1", port: 0, async fetch(request) {
    expect(request.method).toBe("PUT");
    received = await request.text();
    return new Response("", { status: 200 });
  } });
  const repo = (name: string, location: string) => ({
    name, source: "quicksilver", hostname: "mac", paths: [data], location, passwordFile, extraArgs: [],
  });
  const config = { repositories: [repo("nas-hdd", left), repo("hetzner", right)],
    compare: ["nas-hdd", "hetzner"] as [string, string], stateFile: join(directory, "collector.json"),
    pushgatewayUrl: `http://127.0.0.1:${server.port}/metrics`, commandTimeoutSeconds: 5 };
  try {
    await collect(config);
    expect(received).toContain('backup_snapshot_count{source="quicksilver",repo="hetzner"} 0');
    expect(received).toContain('backup_missing_snapshots{source="quicksilver",repo="nas-hdd",destination="hetzner"} 1');
    restic(right, "copy", "--from-repo", left, "--from-password-file", passwordFile);
    await collect(config);
    expect(received).toContain('backup_missing_snapshots{source="quicksilver",repo="nas-hdd",destination="hetzner"} 0');
    const lastGood = JSON.parse(readFileSync(config.stateFile, "utf8"));
    config.repositories[1].location = join(directory, "does-not-exist");
    await collect(config);
    const failed = JSON.parse(readFileSync(config.stateFile, "utf8"));
    expect(failed.repos.hetzner.count).toBe(1);
    expect(failed.repos.hetzner.latest).toBe(lastGood.repos.hetzner.latest);
    expect(failed.repos.hetzner.lastSuccess).toBe(lastGood.repos.hetzner.lastSuccess);
    expect(received).toContain('backup_collection_success{source="quicksilver",repo="hetzner"} 0');
    expect(received).toContain('backup_comparison_success{source="quicksilver"} 0');

    // Hung clients must also publish failures and preserve the last observation.
    const fakeBin = join(directory, "fake-bin");
    mkdirSync(fakeBin);
    writeFileSync(join(fakeBin, "restic"), `#!${process.execPath}\nBun.sleepSync(5000);\n`, { mode: 0o755 });
    const previousPath = process.env.PATH;
    try {
      process.env.PATH = `${fakeBin}:${previousPath}`;
      await collect({ ...config, commandTimeoutSeconds: 0.05 });
      expect(received).toContain('backup_collection_success{source="quicksilver",repo="nas-hdd"} 0');
      expect(JSON.parse(readFileSync(config.stateFile, "utf8")).repos["nas-hdd"].count).toBe(1);
    } finally {
      process.env.PATH = previousPath;
    }

    // A real partial snapshot must still reach the destination, while status
    // reports code 3 even if a later copy/prune step has its own outcome.
    const metricsFile = join(directory, "integration.prom");
    const unreadable = join(directory, "unreadable");
    writeFileSync(unreadable, "cannot be read by restic");
    chmodSync(unreadable, 0o000);
    const backupConfig = join(directory, "backup.json");
    const runnerRepo = (location: string) => ({ location, passwordFile, oldPasswordFile: null, extraArgs: [] });
    writeFileSync(backupConfig, JSON.stringify({
      localRepo: runnerRepo(left), remoteRepos: [runnerRepo(right)], createSnapshots: true,
      paths: [data, unreadable], excludes: [], keepWithin: null,
      statusMetrics: { file: metricsFile, source: "test" },
    }));
    const result = spawnSync(process.execPath, [resolve("modules/backup/backup.ts"), "run-backup", backupConfig], { encoding: "utf8" });
    expect(result.status, result.stderr).toBe(0);
    expect(readFileSync(metricsFile, "utf8")).toContain('backup_partial_unresolved{source="test"} 1');
    expect(readFileSync(metricsFile, "utf8")).toContain('backup_last_restic_exit_code{source="test"} 3');
    expect(JSON.parse(restic(right, "snapshots", "--json")).length).toBe(2);
  } finally {
    server.stop(true);
  }
}, 120000);
