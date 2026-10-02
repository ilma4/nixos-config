//! Persistent Git CLI worker for git-status-client.zsh (no Git library).
//! Byte-length-prefixed request fields; replies are id:branch<US>...<US>oid plus a newline.
use std::ffi::{OsStr, OsString};
use std::io::{self, BufRead, Write};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::{env, str};

fn read_fields(input: &mut impl BufRead, fields: &mut [Vec<u8>]) -> io::Result<()> {
    for field in fields {
        field.clear();
        input.read_until(b'\n', field)?;
        if field.pop() != Some(b'\n') {
            return Err(io::ErrorKind::UnexpectedEof.into());
        }
        field.resize(number(field) as usize, 0);
        input.read_exact(field)?;
    }
    Ok(())
}

struct Request<'a> {
    dir: &'a OsStr,
    path: Option<&'a OsStr>, // None when the request matches the inherited PATH.
    git_env: &'a [[Vec<u8>; 2]], // Name/value pairs from reusable request buffers.
}

impl Request<'_> {
    fn command<S: AsRef<OsStr>>(&self, args: &[S], status: bool) -> Command {
        let mut command = Command::new("git");
        command
            .args([OsStr::new("-C"), self.dir])
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .args(args)
            .envs(self.path.map(|path| ("PATH", path)));
        for [name, value] in self.git_env {
            if !status || name != b"GIT_OPTIONAL_LOCKS" {
                command.env(OsStr::from_bytes(name), OsStr::from_bytes(value));
            }
        }
        command
    }

    fn git<S: AsRef<OsStr>>(&self, args: &[S]) -> Vec<u8> {
        let output = self.command(args, false).output();
        let mut bytes = output.map(|o| o.stdout).unwrap_or_default();
        // Match Zsh command substitution, which strips all trailing newlines.
        bytes.truncate(bytes.iter().rposition(|&c| c != b'\n').map_or(0, |i| i + 1));
        bytes
    }

    fn status(&self, result: &mut Vec<u8>, buffers: &mut [Vec<u8>; 4]) -> Option<()> {
        buffers.iter_mut().for_each(Vec::clear);
        let [buffer, branch, upstream, oid] = buffers;
        // Temporarily inherit this override to avoid copying the whole environment.
        // Only this single-threaded worker's status child sees it.
        env::set_var("GIT_OPTIONAL_LOCKS", "0");
        let args = ["status", "--porcelain=v2", "--branch", "--show-stash"];
        let child = self.command(&args, true).stdout(Stdio::piped()).spawn();
        env::remove_var("GIT_OPTIONAL_LOCKS");
        let mut child = child.ok()?;
        let mut porcelain = io::BufReader::with_capacity(4096, child.stdout.take()?);
        // Stream status through one reusable line instead of retaining every path.
        let mut counts = [0u64; 7]; // staged, unstaged, untracked, conflicted, ahead, behind, stashes
        while porcelain.read_until(b'\n', buffer).ok()? != 0 {
            let line = buffer.strip_suffix(b"\n").unwrap_or(buffer);
            let mut parts = line.splitn(3, |&c| c == b' ');
            match parts.next() {
                Some(b"#") => match (parts.next(), parts.next()) {
                    (Some(b"branch.oid"), Some(value)) => value.clone_into(oid),
                    (Some(b"branch.head"), Some(b"(detached)")) => {}
                    (Some(b"branch.head"), Some(value)) => value.clone_into(branch),
                    (Some(b"branch.upstream"), Some(value)) => value.clone_into(upstream),
                    (Some(b"branch.ab"), Some(value)) => {
                        let mut parts = value.split(|&c| c == b' ');
                        for (count, sign) in counts[4..6].iter_mut().zip([b"+", b"-"]) {
                            let part = parts.next().unwrap_or_default();
                            *count = number(part.strip_prefix(sign).unwrap_or_default());
                        }
                    }
                    (Some(b"stash"), Some(value)) => counts[6] = number(value),
                    _ => {}
                },
                Some(b"1" | b"2") if line.len() >= 4 => {
                    counts[0] += u64::from(line[2] != b'.');
                    counts[1] += u64::from(line[3] != b'.');
                }
                Some(b"u") if line.len() > 1 => counts[3] += 1,
                Some(b"?") if line.len() > 1 => counts[2] += 1,
                _ => {}
            }
            buffer.clear();
        }
        child.wait().ok().filter(|status| status.success())?;
        let mut upstream = upstream.as_slice();
        if !upstream.is_empty() {
            buffer.extend(b"branch.".iter().chain(branch.iter()).chain(b".remote"));
            // Reuse the cleared status line; Git ref names need not be Unicode.
            let mut remote = self
                .git(&[b"config".as_slice(), b"--get", buffer.as_slice()].map(OsStr::from_bytes));
            if !remote.is_empty() && remote != b"." {
                remote.push(b'/');
                upstream = upstream.strip_prefix(remote.as_slice()).unwrap_or(upstream);
            }
        }
        let tags = self.git(&["tag", "--points-at", "HEAD", "--sort=refname"]);
        let tag = tags.rsplit(|&c| c == b'\n').next().unwrap_or_default();
        let mut action: &[u8] = b"";
        let dir = self.git(&["rev-parse", "--absolute-git-dir"]);
        if !dir.is_empty() {
            let mut dir = PathBuf::from(OsString::from_vec(dir));
            action = [
                ("rebase-merge", "rebase"),
                ("rebase-apply", "rebase"),
                ("MERGE_HEAD", "merge"),
                ("CHERRY_PICK_HEAD", "cherry-pick"),
                ("REVERT_HEAD", "revert"),
                ("BISECT_LOG", "bisect"),
            ]
            .into_iter()
            .find_map(|(file, action)| {
                dir.push(file);
                let metadata = dir.metadata();
                dir.pop();
                let metadata = metadata.ok()?;
                (action != "rebase" || metadata.is_dir()).then_some(action.as_bytes())
            })
            .unwrap_or_default();
        }
        for field in [branch.as_slice(), upstream, action] {
            result.extend_from_slice(field);
            result.push(0x1f);
        }
        for count in counts {
            write!(result, "{count}\x1f").ok()?;
        }
        result.extend_from_slice(tag);
        result.push(0x1f);
        result.extend_from_slice(oid);
        Some(())
    }
}

fn number(bytes: &[u8]) -> u64 {
    str::from_utf8(bytes).unwrap_or("").parse().unwrap_or(0)
}

fn run() -> io::Result<()> {
    // Drop inherited Git overrides once; each request supplies its own.
    env::vars_os()
        .filter(|(name, _)| name.as_bytes().starts_with(b"GIT_"))
        .for_each(|(name, _)| env::remove_var(name));
    let inherited_path = env::var_os("PATH");
    let mut input = io::stdin().lock();
    let mut output = io::stdout().lock();
    let mut result = Vec::with_capacity(256);
    // Reuse request fields, the status line and header values across requests.
    let mut fields = std::array::from_fn(|_| Vec::new());
    let mut git_env: Vec<[Vec<u8>; 2]> = Vec::new();
    let mut buffers = std::array::from_fn(|_| Vec::new());
    loop {
        read_fields(&mut input, &mut fields)?;
        let [id, dir, path, count] = &mut fields;
        let count = number(count);
        for index in 0..count {
            git_env.resize_with(git_env.len().max(index as usize + 1), Default::default);
            let pair = &mut git_env[index as usize];
            read_fields(&mut input, pair)?;
            if !pair[0].starts_with(b"GIT_") {
                std::process::exit(1);
            }
        }
        git_env.truncate(count as usize);
        let path = OsStr::from_bytes(path);
        let request = Request {
            dir: OsStr::from_bytes(dir),
            path: (inherited_path.as_deref() != Some(path)).then_some(path),
            git_env: &git_env,
        };
        result.clear();
        result.extend_from_slice(id);
        result.push(b':');
        let _ = request.status(&mut result, &mut buffers);
        result.push(b'\n');
        output.write_all(&result)?;
        output.flush()?;
    }
}

fn main() {
    run().unwrap_or_else(|error| {
        if ![io::ErrorKind::BrokenPipe, io::ErrorKind::UnexpectedEof].contains(&error.kind()) {
            eprintln!("git status daemon: {error}");
            std::process::exit(1);
        }
    });
}
