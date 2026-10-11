import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync, renameSync } from "node:fs";

type Repository = {
  name: string;
  source: string;
  hostname: string;
  paths: string[];
  location: string;
  passwordFile: string;
  extraArgs: string[];
};
type Snapshot = {
  id: string;
  original?: string;
  time: string;
  tree: string;
  hostname: string;
  username?: string;
  uid?: number;
  gid?: number;
  paths: string[];
  excludes?: string[];
  tags?: string[];
};
type Observation = { count: number; latest: number; lastSuccess: number; success: number };
type Comparison = { missingLeft: number; missingRight: number; lastSuccess: number; success: number };
type State = { repos: Record<string, Observation>; comparison?: Comparison };
type Config = {
  repositories: Repository[];
  compare: [string, string];
  stateFile: string;
  pushgatewayUrl: string;
  relayService?: string;
  commandTimeoutSeconds?: number;
};

const sorted = (values: string[] = []) => [...values].sort();

export function selectSnapshots(snapshots: Snapshot[], repo: Pick<Repository, "hostname" | "paths">): Snapshot[] {
  assert(Array.isArray(snapshots), "Expected a snapshot list");
  return snapshots.filter(snapshot => snapshot.hostname === repo.hostname &&
    JSON.stringify(sorted(snapshot.paths)) === JSON.stringify(sorted(repo.paths)));
}

export function snapshotKey(snapshot: Snapshot): string {
  assert(/^[a-f0-9]{64}$/.test(snapshot.id), "Invalid snapshot ID");
  assert(Number.isFinite(Date.parse(snapshot.time)), "Invalid snapshot time");
  assert(typeof snapshot.tree === "string", "Missing snapshot tree");
  const identity = snapshot.original && !/^0+$/.test(snapshot.original) ? snapshot.original : snapshot.id;
  // Copying changes id/parent. Original identity plus content metadata detects
  // missing historical snapshots and rewritten snapshots with the same original.
  return JSON.stringify([
    identity, snapshot.time, snapshot.tree, snapshot.hostname, snapshot.username,
    snapshot.uid, snapshot.gid, sorted(snapshot.paths), sorted(snapshot.excludes), sorted(snapshot.tags),
  ]);
}

export function compareSnapshots(left: Snapshot[], right: Snapshot[]): [number, number] {
  const leftKeys = new Set(left.map(snapshotKey));
  const rightKeys = new Set(right.map(snapshotKey));
  return [
    [...leftKeys].filter(key => !rightKeys.has(key)).length,
    [...rightKeys].filter(key => !leftKeys.has(key)).length,
  ];
}

function loadState(file: string): State {
  try {
    const state = JSON.parse(readFileSync(file, "utf8"));
    assert(state.repos && typeof state.repos === "object", "Invalid collector state");
    return state;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    return { repos: {} };
  }
}

function relayState(service?: string): { running: number; started: number; success: number } {
  if (!service) return { running: 0, started: 0, success: 1 };
  const result = spawnSync("systemctl", ["show", service, "-p", "ActiveState", "-p", "InactiveExitTimestampMonotonic"],
    { encoding: "utf8", timeout: 10000 });
  if (result.error || result.status !== 0) return { running: 0, started: 0, success: 0 };
  const properties = Object.fromEntries(result.stdout.trim().split("\n").map(line => line.split("=")));
  const running = ["activating", "active", "deactivating"].includes(properties.ActiveState) ? 1 : 0;
  const start = Number(properties.InactiveExitTimestampMonotonic) / 1e6;
  const uptime = Number(readFileSync("/proc/uptime", "utf8").split(" ")[0]);
  if (!Number.isFinite(start) || !Number.isFinite(uptime) || !properties.ActiveState) {
    return { running: 0, started: 0, success: 0 };
  }
  return { running, started: running ? Math.floor(Date.now() / 1000 - uptime + start) : 0, success: 1 };
}

export async function collect(config: Config): Promise<string> {
  const state = loadState(config.stateFile);
  const now = Math.floor(Date.now() / 1000);
  const snapshots = new Map<string, Snapshot[]>();
  const observations: Record<string, Observation> = {};
  for (const repo of config.repositories) {
    const observation = { ...(state.repos[repo.name] ?? { count: 0, latest: 0, lastSuccess: 0 }), success: 0 };
    try {
      const result = spawnSync("restic", ["-r", repo.location, "--password-file", repo.passwordFile,
        ...repo.extraArgs, "--no-lock", "snapshots", "--json"], {
        encoding: "utf8", timeout: (config.commandTimeoutSeconds ?? 300) * 1000,
        killSignal: "SIGKILL", maxBuffer: 100 * 1024 ** 2,
      });
      if (result.error) throw result.error;
      assert(result.status === 0, `restic snapshots failed: ${result.stderr}`);
      const selected = selectSnapshots(JSON.parse(result.stdout), repo);
      selected.forEach(snapshotKey);
      observation.count = selected.length;
      observation.latest = selected.reduce((latest, snapshot) => Math.max(latest, Date.parse(snapshot.time) / 1000), 0);
      observation.lastSuccess = Math.floor(Date.now() / 1000);
      observation.success = 1;
      snapshots.set(repo.name, selected);
    } catch (error) {
      console.error(`Failed to inspect ${repo.name}: ${error}`);
    }
    observations[repo.name] = observation;
  }
  const [leftName, rightName] = config.compare;
  const leftRepo = config.repositories.find(repo => repo.name === leftName);
  const rightRepo = config.repositories.find(repo => repo.name === rightName);
  assert(leftRepo && rightRepo && leftRepo.source === rightRepo.source, "Invalid comparison repositories");
  const comparison = { ...(state.comparison ?? { missingLeft: 0, missingRight: 0, lastSuccess: 0 }), success: 0 };
  if (snapshots.has(leftName) && snapshots.has(rightName)) {
    [comparison.missingLeft, comparison.missingRight] = compareSnapshots(snapshots.get(leftName)!, snapshots.get(rightName)!);
    comparison.lastSuccess = Math.floor(Date.now() / 1000);
    comparison.success = 1;
  }

  const lines: string[] = [];
  function metric(name: string, help: string, samples: [Record<string, string>, number][]) {
    lines.push(`# HELP ${name} ${help}`, `# TYPE ${name} gauge`);
    for (const [labels, value] of samples) {
      assert(Number.isFinite(value), `Invalid value for ${name}`);
      const labelText = Object.entries(labels).map(([name, value]) => `${name}=${JSON.stringify(value)}`).join(",");
      lines.push(`${name}${labelText ? `{${labelText}}` : ""} ${value}`);
    }
  }
  const repositorySamples = (field: keyof Observation): [Record<string, string>, number][] =>
    config.repositories.map(repo => [{ source: repo.source, repo: repo.name }, observations[repo.name][field]]);
  metric("backup_snapshot_count", "Number of matching snapshots currently stored.", repositorySamples("count"));
  metric("backup_latest_snapshot_timestamp_seconds", "Creation time of the newest matching snapshot, or zero for an empty repository.", repositorySamples("latest"));
  metric("backup_collection_success", "Whether the latest repository inspection succeeded.", repositorySamples("success"));
  metric("backup_collection_last_success_timestamp_seconds", "Time of the latest successful repository inspection.", repositorySamples("lastSuccess"));
  metric("backup_missing_snapshots", "Snapshots present in repo but absent or different in destination.", [
    [{ source: leftRepo.source, repo: leftName, destination: rightName }, comparison.missingLeft],
    [{ source: leftRepo.source, repo: rightName, destination: leftName }, comparison.missingRight],
  ]);
  const sourceLabels = { source: leftRepo.source };
  metric("backup_comparison_success", "Whether both repositories could be compared in this collection.", [[sourceLabels, comparison.success]]);
  metric("backup_comparison_last_success_timestamp_seconds", "Time of the latest successful comparison.", [[sourceLabels, comparison.lastSuccess]]);
  const relay = relayState(config.relayService);
  metric("backup_relay_running", "Whether the relay is currently starting, copying or stopping.", [[sourceLabels, relay.running]]);
  metric("backup_relay_started_timestamp_seconds", "Start time of the active relay, or zero when inactive.", [[sourceLabels, relay.started]]);
  metric("backup_relay_state_success", "Whether the relay service state could be inspected.", [[sourceLabels, relay.success]]);
  metric("backup_monitor_last_run_timestamp_seconds", "Start time of the latest collector run.", [[{}, now]]);
  const output = `${lines.join("\n")}\n`;
  const temporary = `${config.stateFile}.${process.pid}.tmp`;
  writeFileSync(temporary, JSON.stringify({ repos: observations, comparison }), { mode: 0o600 });
  renameSync(temporary, config.stateFile);
  const response = await fetch(config.pushgatewayUrl, {
    method: "PUT", body: output, headers: { "Content-Type": "text/plain; version=0.0.4" },
    signal: AbortSignal.timeout(10000),
  });
  assert(response.ok, `Pushgateway returned ${response.status}`);
  return output;
}

if (import.meta.main) {
  assert(process.argv[2], "Expected collector config file");
  await collect(JSON.parse(readFileSync(process.argv[2], "utf8")));
}
