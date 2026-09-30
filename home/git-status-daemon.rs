//! Persistent Git CLI worker for git-status-client.zsh (no Git library).
//! Requests are Zsh ${(q)value} fields, one per line; responses are
//! id:branch<US>upstream<US>...<US>oid followed by a newline.
use std::env;
use std::ffi::OsString;
use std::io::{self, BufRead, Write};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::path::PathBuf;
use std::process::{Command, Stdio};

// Decode the backslash quoting and embedded $'...' emitted by Zsh's (q).
// Work on bytes so non-UTF-8 Unix paths and environment values survive too.
fn unquote(input: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(input.len());
    let mut i = 0;
    let mut ansi = false;
    while i < input.len() {
        if !ansi && input[i..].starts_with(b"$'") {
            ansi = true;
            i += 2;
        } else if ansi && input[i] == b'\'' {
            ansi = false;
            i += 1;
        } else if !ansi && input[i..].starts_with(b"''") {
            i += 2;
        } else if input[i] == b'\\' && i + 1 < input.len() {
            i += 1;
            let c = input[i];
            i += 1;
            if ansi {
                match c {
                    b'a' => out.push(7),
                    b'b' => out.push(8),
                    b'e' | b'E' => out.push(27),
                    b'f' => out.push(12),
                    b'n' => out.push(b'\n'),
                    b'r' => out.push(b'\r'),
                    b't' => out.push(b'\t'),
                    b'v' => out.push(11),
                    b'0'..=b'7' => {
                        let mut value = (c - b'0') as u16;
                        for _ in 0..2 {
                            if i < input.len() && (b'0'..=b'7').contains(&input[i]) {
                                value = value * 8 + (input[i] - b'0') as u16;
                                i += 1;
                            } else {
                                break;
                            }
                        }
                        out.push(value as u8);
                    }
                    _ => out.push(c),
                }
            } else {
                out.push(c);
            }
        } else {
            out.push(input[i]);
            i += 1;
        }
    }
    out
}

fn read_field(input: &mut impl BufRead) -> io::Result<Option<Vec<u8>>> {
    let mut line = Vec::new();
    if input.read_until(b'\n', &mut line)? == 0 || line.last() != Some(&b'\n') {
        return Ok(None);
    }
    line.pop();
    Ok(Some(unquote(&line)))
}

struct Request {
    dir: OsString,
    path: OsString,
    git_env: Vec<(OsString, OsString)>,
}

impl Request {
    fn git(
        &self,
        inherited_git_names: &[OsString],
        args: &[&str],
        optional_locks: bool,
    ) -> Option<Vec<u8>> {
        let mut command = self.command(inherited_git_names);
        command.args(args);
        if optional_locks {
            command.env("GIT_OPTIONAL_LOCKS", "0");
        }
        let output = command.output().ok()?;
        // Only the status command's exit code gates a response. The original
        // formatter still uses stdout from auxiliary commands that fail.
        if optional_locks && !output.status.success() {
            return None;
        }
        let mut bytes = output.stdout;
        // Match Zsh command substitution, which strips all trailing newlines.
        while bytes.last() == Some(&b'\n') {
            bytes.pop();
        }
        Some(bytes)
    }

    fn status(&self, inherited_git_names: &[OsString]) -> Option<Vec<u8>> {
        let porcelain = self.git(
            inherited_git_names,
            &["status", "--porcelain=v2", "--branch", "--show-stash"],
            true,
        )?;
        let mut fields: [Vec<u8>; 12] = Default::default();
        let mut counts = [0u64; 7]; // staged, unstaged, untracked, conflicted, ahead, behind, stashes
        for line in porcelain.split(|&c| c == b'\n') {
            if let Some(value) = line.strip_prefix(b"# branch.oid ") {
                fields[11] = value.to_vec();
            } else if let Some(value) = line.strip_prefix(b"# branch.head ") {
                if value != b"(detached)" {
                    fields[0] = value.to_vec();
                }
            } else if let Some(value) = line.strip_prefix(b"# branch.upstream ") {
                fields[1] = value.to_vec();
            } else if let Some(value) = line.strip_prefix(b"# branch.ab ") {
                let mut parts = value.split(|&c| c == b' ');
                counts[4] = number(
                    parts
                        .next()
                        .unwrap_or_default()
                        .strip_prefix(b"+")
                        .unwrap_or_default(),
                );
                counts[5] = number(
                    parts
                        .next()
                        .unwrap_or_default()
                        .strip_prefix(b"-")
                        .unwrap_or_default(),
                );
            } else if let Some(value) = line.strip_prefix(b"# stash ") {
                counts[6] = number(value);
            } else if (line.starts_with(b"1 ") || line.starts_with(b"2 ")) && line.len() >= 4 {
                counts[0] += u64::from(line[2] != b'.');
                counts[1] += u64::from(line[3] != b'.');
            } else if line.starts_with(b"u ") {
                counts[3] += 1;
            } else if line.starts_with(b"? ") {
                counts[2] += 1;
            }
        }
        if !fields[1].is_empty() {
            let mut key = b"branch.".to_vec();
            key.extend_from_slice(&fields[0]);
            key.extend_from_slice(b".remote");
            // Git ref names are byte strings; don't require Unicode here.
            let mut command = self.command(inherited_git_names);
            command
                .args(["config", "--get"])
                .arg(OsString::from_vec(key));
            if let Ok(output) = command.output() {
                let mut remote = output.stdout.as_slice();
                while let Some(trimmed) = remote.strip_suffix(b"\n") {
                    remote = trimmed;
                }
                if !remote.is_empty() && remote != b"." {
                    let mut prefix = remote.to_vec();
                    prefix.push(b'/');
                    if fields[1].starts_with(&prefix) {
                        fields[1].drain(..prefix.len());
                    }
                }
            }
        }
        if let Some(tags) = self.git(
            inherited_git_names,
            &["tag", "--points-at", "HEAD", "--sort=refname"],
            false,
        ) {
            fields[10] = tags
                .rsplit(|&c| c == b'\n')
                .next()
                .unwrap_or_default()
                .to_vec();
        }
        if let Some(dir) = self.git(
            inherited_git_names,
            &["rev-parse", "--absolute-git-dir"],
            false,
        ) {
            if !dir.is_empty() {
                let dir = PathBuf::from(OsString::from_vec(dir));
                fields[2] =
                    if dir.join("rebase-merge").is_dir() || dir.join("rebase-apply").is_dir() {
                        b"rebase".to_vec()
                    } else {
                        [
                            ("MERGE_HEAD", "merge"),
                            ("CHERRY_PICK_HEAD", "cherry-pick"),
                            ("REVERT_HEAD", "revert"),
                            ("BISECT_LOG", "bisect"),
                        ]
                        .into_iter()
                        .find(|(file, _)| dir.join(file).exists())
                        .map(|(_, action)| action.as_bytes().to_vec())
                        .unwrap_or_default()
                    };
            }
        }
        for (field, count) in fields[3..10].iter_mut().zip(counts) {
            *field = count.to_string().into_bytes();
        }
        Some(fields.join(&0x1f))
    }

    fn command(&self, inherited_git_names: &[OsString]) -> Command {
        let mut command = Command::new("git");
        command
            .arg("-C")
            .arg(&self.dir)
            .env("PATH", &self.path)
            .stdin(Stdio::null())
            .stderr(Stdio::null());
        for name in inherited_git_names {
            command.env_remove(name);
        }
        for (name, value) in &self.git_env {
            command.env(name, value);
        }
        command
    }
}

fn number(bytes: &[u8]) -> u64 {
    std::str::from_utf8(bytes)
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(0)
}

fn run() -> io::Result<()> {
    let inherited_git_names: Vec<_> = env::vars_os()
        .map(|(name, _)| name)
        .filter(|name| name.as_bytes().starts_with(b"GIT_"))
        .collect();
    let mut input = io::stdin().lock();
    let mut output = io::BufWriter::new(io::stdout().lock());
    while let Some(id) = read_field(&mut input)? {
        let Some(dir) = read_field(&mut input)? else {
            break;
        };
        let Some(path) = read_field(&mut input)? else {
            break;
        };
        let Some(count) = read_field(&mut input)? else {
            break;
        };
        let mut request = Request {
            dir: OsString::from_vec(dir),
            path: OsString::from_vec(path),
            git_env: Vec::new(),
        };
        for _ in 0..number(&count) {
            let Some(name) = read_field(&mut input)? else {
                return Ok(());
            };
            let Some(value) = read_field(&mut input)? else {
                return Ok(());
            };
            if !name.starts_with(b"GIT_") {
                std::process::exit(1);
            }
            request
                .git_env
                .push((OsString::from_vec(name), OsString::from_vec(value)));
        }
        let result = request.status(&inherited_git_names).unwrap_or_default();
        output.write_all(&id)?;
        output.write_all(b":")?;
        output.write_all(&result)?;
        output.write_all(b"\n")?;
        output.flush()?;
    }
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        if error.kind() != io::ErrorKind::BrokenPipe {
            eprintln!("git status daemon: {error}");
            std::process::exit(1);
        }
    }
}
