import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import assert from "node:assert/strict";

type Repo = {
  location: string;
  passwordFile: string;
  oldPasswordFile: string | null;
  extraArgs: string[];
};

type BackupConfig = {
  localRepo: Repo;
  remoteRepos: Repo[];
  createSnapshots: boolean;
  paths: string[];
  excludes: string[];
  keepWithin: string | null;
};

function logInfo(message: string, condition: boolean = true): void {
  if (!condition) return;
  const timestamp = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  console.log(message.replace(/\n$/, "").split("\n").map(line => `${timestamp} ${line}`).join("\n"));
}

const readJson = <T>(file: string): T => JSON.parse(readFileSync(file, "utf8"));
const withPassword = (repo: Repo, passwordFile: string): Repo => ({ ...repo, passwordFile });

function runRestic(repo: Repo, ...args: string[]) {
  const resticArgs = ["-r", repo.location, "--password-file", repo.passwordFile, ...repo.extraArgs, ...args];
  const result = spawnSync("restic", resticArgs, { encoding: "utf8", maxBuffer: 100 * 1024 ** 2 });
  if (result.error) throw result.error;
  return result;
}

function mustRunRestic(repo: Repo, ...args: string[]): void {
  const { status, stderr } = runRestic(repo, ...args);
  assert(status === 0, `restic failed for ${repo.location}: ${stderr}`);
}

const repoExists = (repo: Repo): boolean => runRestic(repo, "cat", "config").status === 0;

const repoExistsOrExistsWithOldPassword = (repo: Repo): boolean => repoExists(repo) ||
  (repo.oldPasswordFile !== null && repoExists(withPassword(repo, repo.oldPasswordFile)));

const fromRepoArgs = ({ location, passwordFile, extraArgs }: Repo): string[] =>
  ["--from-repo", location, "--from-password-file", passwordFile, ...extraArgs];

function readChunker(repo: Repo): string {
  const stdout = runRestic(repo, "--json", "cat", "config").stdout;
  const { chunker_polynomial: chunker } = JSON.parse(stdout) as Record<string, unknown>;
  assert(typeof chunker === "string", "invalid repo chunker");
  return chunker;
}

function initRepos(repos: Repo[]): void {
  const sourceRepo = repos.find(repoExists);
  const missingRepos = repos.filter(repo => !repoExistsOrExistsWithOldPassword(repo));
  if (!missingRepos.length) return;
  assert(sourceRepo, "No repo is accessible with the current password");
  missingRepos.forEach(repo => mustRunRestic(repo, "init", "--copy-chunker-params", ...fromRepoArgs(sourceRepo)));
}

function rotateKey(repo: Repo): void {
  const status = runRestic(repo, "cat", "config").status;
  if (status === 0) return;
  assert(status === 12, "Failed to check repository password");
  assert(repo.oldPasswordFile !== null, `No old password for ${repo.location}`);
  const oldRepo = withPassword(repo, repo.oldPasswordFile);
  mustRunRestic(oldRepo, "key", "passwd", "--new-password-file", repo.passwordFile);
}

function runBackup({ localRepo, remoteRepos, createSnapshots, paths, excludes, keepWithin }: BackupConfig): void {
  if (createSnapshots) {
    const { status, stderr } = runRestic(localRepo, "backup", ...excludes.flatMap(path => ["--exclude", path]), ...paths);
    if (status === 3) logInfo(`backup can't read some paths:\n${stderr}`);
    else assert(status === 0, `Backup failed: ${stderr}`);
    logInfo("backup successfully made");
  }

  const localChunker = readChunker(localRepo);
  assert(remoteRepos.every(repo => readChunker(repo) === localChunker, "Repository chunkers differ"));
  for (const repo of remoteRepos) {
    logInfo(`copying backup to ${repo.location}`);
    mustRunRestic(repo, "copy", ...fromRepoArgs(localRepo));
    logInfo(`backup copied to ${repo.location}`);
  }

  if (remoteRepos.length) logInfo("backup copied to all remote repos");
  if (keepWithin === null) return;
  mustRunRestic(localRepo, "forget", "--prune", "--keep-within", keepWithin);
  logInfo("backup successfully pruned");
}

function main(): void {
  const args = process.argv.slice(2);
  const [command, file] = args;
  logInfo(`backup script started: ${JSON.stringify(args)}`);
  assert(command && file, "Expected command and config file");
  switch (command) {
    case "init-repos": initRepos(readJson<Repo[]>(file)); break;
    case "rotate-keys": readJson<Repo[]>(file).forEach(rotateKey); break;
    case "run-backup": runBackup(readJson<BackupConfig>(file)); break;
    default: throw new Error(`Unknown command: ${command}`);
  }
}

main();
