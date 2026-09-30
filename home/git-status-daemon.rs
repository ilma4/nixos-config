//! Persistent Git CLI worker for git-status-client.zsh (no Git library).
//! Requests are Zsh ${(q)value} fields, one per line; responses are
//! id:branch<US>upstream<US>...<US>oid followed by a newline.
use std::env;
use std::ffi::{OsStr, OsString};
use std::io::{self, BufRead, Write};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::path::PathBuf;
use std::process::{Command, Stdio};

// Decode the backslash quoting and embedded $'...' emitted by Zsh's (q).
// Work on bytes so non-UTF-8 Unix paths and environment values survive too.
fn unquote(input: Vec<u8>) -> Vec<u8> {
    if !input.iter().any(|&c| c == b'\\' || c == b'\'') {
        return input;
    }
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

fn read_fields<const N: usize>(input: &mut impl BufRead) -> io::Result<Option<[Vec<u8>; N]>> {
    let mut fields = std::array::from_fn(|_| Vec::new());
    for field in &mut fields {
        if input.read_until(b'\n', field)? == 0 || field.last() != Some(&b'\n') {
            return Ok(None);
        }
        field.pop();
        *field = unquote(std::mem::take(field));
    }
    Ok(Some(fields))
}

struct Request {
    dir: OsString,
    path: Option<OsString>, // None when the request matches the inherited PATH.
    git_env: Vec<(OsString, OsString)>,
}

impl Request {
    fn git<S: AsRef<OsStr>>(
        &self,
        inherited_git_names: &[OsString],
        args: &[S],
        optional_locks: bool,
    ) -> Option<Vec<u8>> {
        let mut command = Command::new("git");
        command
            .arg("-C")
            .arg(&self.dir)
            .stdin(Stdio::null())
            .stderr(Stdio::null());
        // Leaving an unchanged PATH inherited avoids rebuilding the entire
        // environment for auxiliary commands with no Git overrides.
        if let Some(path) = &self.path {
            command.env("PATH", path);
        }
        for name in inherited_git_names {
            command.env_remove(name);
        }
        for (name, value) in &self.git_env {
            command.env(name, value);
        }
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
        // Borrow status fields instead of copying them into separate buffers.
        let mut fields: [&[u8]; 12] = [b""; 12];
        let mut counts = [0u64; 7]; // staged, unstaged, untracked, conflicted, ahead, behind, stashes
        for line in porcelain.split(|&c| c == b'\n') {
            if let Some(value) = line.strip_prefix(b"# branch.oid ") {
                fields[11] = value;
            } else if let Some(value) = line.strip_prefix(b"# branch.head ") {
                if value != b"(detached)" {
                    fields[0] = value;
                }
            } else if let Some(value) = line.strip_prefix(b"# branch.upstream ") {
                fields[1] = value;
            } else if let Some(value) = line.strip_prefix(b"# branch.ab ") {
                let mut parts = value.split(|&c| c == b' ');
                for (count, sign) in counts[4..6].iter_mut().zip([b"+", b"-"]) {
                    *count = number(
                        parts
                            .next()
                            .and_then(|part| part.strip_prefix(sign))
                            .unwrap_or_default(),
                    );
                }
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
            key.extend_from_slice(fields[0]);
            key.extend_from_slice(b".remote");
            // Git ref names are byte strings; don't require Unicode here.
            if let Some(mut remote) = self.git(
                inherited_git_names,
                &[
                    OsStr::new("config"),
                    OsStr::new("--get"),
                    OsStr::from_bytes(&key),
                ],
                false,
            ) {
                if !remote.is_empty() && remote != b"." {
                    remote.push(b'/');
                    if let Some(branch) = fields[1].strip_prefix(remote.as_slice()) {
                        fields[1] = branch;
                    }
                }
            }
        }
        let tags = self
            .git(
                inherited_git_names,
                &["tag", "--points-at", "HEAD", "--sort=refname"],
                false,
            )
            .unwrap_or_default();
        fields[10] = tags.rsplit(|&c| c == b'\n').next().unwrap_or_default();
        if let Some(dir) = self
            .git(
                inherited_git_names,
                &["rev-parse", "--absolute-git-dir"],
                false,
            )
            .filter(|dir| !dir.is_empty())
        {
            let dir = PathBuf::from(OsString::from_vec(dir));
            fields[2] = if dir.join("rebase-merge").is_dir() || dir.join("rebase-apply").is_dir() {
                b"rebase"
            } else {
                [
                    ("MERGE_HEAD", "merge"),
                    ("CHERRY_PICK_HEAD", "cherry-pick"),
                    ("REVERT_HEAD", "revert"),
                    ("BISECT_LOG", "bisect"),
                ]
                .into_iter()
                .find(|(file, _)| dir.join(file).exists())
                .map(|(_, action)| action.as_bytes())
                .unwrap_or_default()
            };
        }
        // Write counts directly into the response, avoiding seven allocations.
        let mut result =
            Vec::with_capacity(fields.iter().map(|field| field.len()).sum::<usize>() + 32);
        for (index, field) in fields.iter().enumerate() {
            if index > 0 {
                result.push(0x1f);
            }
            if (3..10).contains(&index) {
                write!(result, "{}", counts[index - 3]).ok()?;
            } else {
                result.extend_from_slice(field);
            }
        }
        Some(result)
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
    let inherited_path = env::var_os("PATH");
    let mut input = io::stdin().lock();
    let mut output = io::BufWriter::new(io::stdout().lock());
    while let Some([id, dir, path, count]) = read_fields(&mut input)? {
        let path = OsString::from_vec(path);
        let mut request = Request {
            dir: OsString::from_vec(dir),
            path: (inherited_path.as_ref() != Some(&path)).then_some(path),
            git_env: Vec::new(),
        };
        for _ in 0..number(&count) {
            let Some([name, value]) = read_fields(&mut input)? else {
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
