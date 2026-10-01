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
fn unquote(input: &mut Vec<u8>) {
    let mut i = input
        .iter()
        .position(|&c| c == b'\\' || c == b'\'' || c == b'$')
        .unwrap_or(input.len());
    let mut written = i;
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
            input[written] = match (ansi, c) {
                (true, b'0'..=b'7') => {
                    let mut value = (c - b'0') as u16;
                    for _ in 0..2 {
                        if i == input.len() || !(b'0'..=b'7').contains(&input[i]) {
                            break;
                        }
                        value = value * 8 + (input[i] - b'0') as u16;
                        i += 1;
                    }
                    value as u8
                }
                (true, b'a') => 7,
                (true, b'b') => 8,
                (true, b'e' | b'E') => 27,
                (true, b'f') => 12,
                (true, b'n') => b'\n',
                (true, b'r') => b'\r',
                (true, b't') => b'\t',
                (true, b'v') => 11,
                _ => c,
            };
            written += 1;
        } else {
            input[written] = input[i];
            written += 1;
            i += 1;
        }
    }
    input.truncate(written);
}

fn read_fields<const N: usize>(input: &mut impl BufRead) -> io::Result<Option<[Vec<u8>; N]>> {
    let mut fields = std::array::from_fn(|_| Vec::new());
    for field in &mut fields {
        if input.read_until(b'\n', field)? == 0 || field.last() != Some(&b'\n') {
            return Ok(None);
        }
        field.pop();
        unquote(field);
    }
    Ok(Some(fields))
}

struct Request {
    dir: OsString,
    path: Option<OsString>, // None when the request matches the inherited PATH.
    git_env: Vec<(OsString, OsString)>,
}

impl Request {
    fn command<S: AsRef<OsStr>>(&self, args: &[S]) -> Command {
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
        command.envs(self.git_env.iter().map(|(name, value)| (name, value)));
        command.args(args);
        command
    }

    fn git<S: AsRef<OsStr>>(&self, args: &[S]) -> Vec<u8> {
        let mut bytes = self
            .command(args)
            .output()
            .map(|o| o.stdout)
            .unwrap_or_default();
        // Match Zsh command substitution, which strips all trailing newlines.
        while bytes.last() == Some(&b'\n') {
            bytes.pop();
        }
        bytes
    }

    fn status(&self) -> Option<Vec<u8>> {
        let mut child = self
            .command(&["status", "--porcelain=v2", "--branch", "--show-stash"])
            .env("GIT_OPTIONAL_LOCKS", "0")
            .stdout(Stdio::piped())
            .spawn()
            .ok()?;
        let mut porcelain = io::BufReader::new(child.stdout.take()?);
        // Stream status through one reusable line instead of retaining every path.
        let (mut branch, mut upstream, mut oid) = (Vec::new(), Vec::new(), Vec::new());
        let mut counts = [0u64; 7]; // staged, unstaged, untracked, conflicted, ahead, behind, stashes
        let mut line = Vec::new();
        while porcelain.read_until(b'\n', &mut line).ok()? != 0 {
            if line.last() == Some(&b'\n') {
                line.pop();
            }
            let mut parts = line.splitn(3, |&c| c == b' ');
            match (parts.next(), parts.next(), parts.next()) {
                (Some(b"#"), Some(b"branch.oid"), Some(value)) => oid = value.to_vec(),
                (Some(b"#"), Some(b"branch.head"), Some(value)) if value != b"(detached)" => {
                    branch = value.to_vec();
                }
                (Some(b"#"), Some(b"branch.upstream"), Some(value)) => upstream = value.to_vec(),
                (Some(b"#"), Some(b"branch.ab"), Some(value)) => {
                    let mut parts = value.split(|&c| c == b' ');
                    for (count, sign) in counts[4..6].iter_mut().zip([b"+", b"-"]) {
                        let part = parts.next().unwrap_or_default();
                        *count = number(part.strip_prefix(sign).unwrap_or_default());
                    }
                }
                (Some(b"#"), Some(b"stash"), Some(value)) => counts[6] = number(value),
                (Some(b"1" | b"2"), _, _) if line.len() >= 4 => {
                    counts[0] += u64::from(line[2] != b'.');
                    counts[1] += u64::from(line[3] != b'.');
                }
                (Some(b"u"), Some(_), _) => counts[3] += 1,
                (Some(b"?"), Some(_), _) => counts[2] += 1,
                _ => {}
            }
            line.clear();
        }
        if !child.wait().ok()?.success() {
            return None;
        }
        if !upstream.is_empty() {
            let key = [b"branch.".as_slice(), &branch, b".remote"].concat();
            // Git ref names are byte strings; don't require Unicode here.
            let mut remote = self.git(&[
                OsStr::new("config"),
                OsStr::new("--get"),
                OsStr::from_bytes(&key),
            ]);
            if !remote.is_empty() && remote != b"." {
                remote.push(b'/');
                if upstream.starts_with(&remote) {
                    upstream.drain(..remote.len());
                }
            }
        }
        let tags = self.git(&["tag", "--points-at", "HEAD", "--sort=refname"]);
        let tag = tags.rsplit(|&c| c == b'\n').next().unwrap_or_default();
        let mut action: &[u8] = b"";
        let dir = self.git(&["rev-parse", "--absolute-git-dir"]);
        if !dir.is_empty() {
            let dir = PathBuf::from(OsString::from_vec(dir));
            action = if dir.join("rebase-merge").is_dir() || dir.join("rebase-apply").is_dir() {
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
        let mut result =
            Vec::with_capacity(branch.len() + upstream.len() + tag.len() + oid.len() + 48);
        for field in [branch.as_slice(), upstream.as_slice(), action] {
            result.extend_from_slice(field);
            result.push(0x1f);
        }
        for count in counts {
            write!(result, "{count}\x1f").ok()?;
        }
        result.extend_from_slice(tag);
        result.push(0x1f);
        result.extend_from_slice(&oid);
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
    // This single-threaded worker forwards Git variables only from each request.
    // Clear inherited overrides once so commands can inherit the rest unchanged.
    for (name, _) in env::vars_os() {
        if name.as_bytes().starts_with(b"GIT_") {
            env::remove_var(name);
        }
    }
    let inherited_path = env::var_os("PATH");
    let mut input = io::stdin().lock();
    let mut output = io::BufWriter::with_capacity(4096, io::stdout().lock());
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
        let result = request.status().unwrap_or_default();
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
