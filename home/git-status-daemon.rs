//! Persistent Git CLI worker for git-status-client.zsh (no Git library).
//! Requests are raw fields prefixed by their byte length and a newline; responses are
//! id:branch<US>upstream<US>...<US>oid followed by a newline.
use std::env;
use std::ffi::{OsStr, OsString};
use std::io::{self, BufRead, Write};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::path::PathBuf;
use std::process::{Command, Stdio};

fn read_fields(input: &mut impl BufRead, fields: &mut [Vec<u8>]) -> io::Result<bool> {
    for field in fields {
        field.clear();
        if input.read_until(b'\n', field)? == 0 || field.last() != Some(&b'\n') {
            return Ok(false);
        }
        field.resize(number(&field[..field.len() - 1]) as usize, 0);
        match input.read_exact(field) {
            Err(error) if error.kind() == io::ErrorKind::UnexpectedEof => return Ok(false),
            result => result?,
        }
    }
    Ok(true)
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

    fn status(&self, result: &mut Vec<u8>, buffer: &mut Vec<u8>) -> Option<()> {
        buffer.clear();
        // Temporarily inherit this override to avoid copying the whole environment.
        // Only this single-threaded worker's status child sees it.
        env::set_var("GIT_OPTIONAL_LOCKS", "0");
        let args = ["status", "--porcelain=v2", "--branch", "--show-stash"];
        let child = self.command(&args, true).stdout(Stdio::piped()).spawn();
        env::remove_var("GIT_OPTIONAL_LOCKS");
        let mut child = child.ok()?;
        let mut porcelain = io::BufReader::with_capacity(4096, child.stdout.take()?);
        // Stream status through one reusable line instead of retaining every path.
        let (mut branch, mut upstream, mut oid) = (Vec::new(), Vec::new(), Vec::new());
        let mut counts = [0u64; 7]; // staged, unstaged, untracked, conflicted, ahead, behind, stashes
        while porcelain.read_until(b'\n', buffer).ok()? != 0 {
            let line = buffer.strip_suffix(b"\n").unwrap_or(buffer);
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
            buffer.clear();
        }
        if !child.wait().ok()?.success() {
            return None;
        }
        let mut upstream = upstream.as_slice();
        if !upstream.is_empty() {
            let key = [b"branch.".as_slice(), &branch, b".remote"].concat();
            // Git ref names are byte strings; don't require Unicode here.
            let mut remote =
                self.git(&[b"config".as_slice(), b"--get", &key].map(OsStr::from_bytes));
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
                let found = match action {
                    "rebase" => dir.is_dir(),
                    _ => dir.exists(),
                };
                dir.pop();
                found.then_some(action.as_bytes())
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
        result.extend_from_slice(&oid);
        Some(())
    }
}

fn number(bytes: &[u8]) -> u64 {
    let text = std::str::from_utf8(bytes).unwrap_or("");
    text.parse().unwrap_or(0)
}

fn run() -> io::Result<()> {
    // Drop inherited Git overrides once; each request supplies its own.
    for (name, _) in env::vars_os() {
        if name.as_bytes().starts_with(b"GIT_") {
            env::remove_var(name);
        }
    }
    let inherited_path = env::var_os("PATH");
    let mut input = io::stdin().lock();
    let mut output = io::stdout().lock();
    let mut result = Vec::with_capacity(256);
    // Reuse raw fields; the consumed count buffer doubles as the status line.
    let mut fields = std::array::from_fn(|_| Vec::new());
    let mut git_env: Vec<[Vec<u8>; 2]> = Vec::new();
    while read_fields(&mut input, &mut fields)? {
        let [id, dir, path, buffer] = &mut fields;
        let count = number(buffer);
        for index in 0..count {
            git_env.resize_with(git_env.len().max(index as usize + 1), Default::default);
            let pair = &mut git_env[index as usize];
            if !read_fields(&mut input, pair)? {
                return Ok(());
            }
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
        let _ = request.status(&mut result, buffer);
        result.push(b'\n');
        output.write_all(&result)?;
        output.flush()?;
    }
    Ok(())
}

fn main() {
    run().unwrap_or_else(|error| {
        if error.kind() != io::ErrorKind::BrokenPipe {
            eprintln!("git status daemon: {error}");
            std::process::exit(1);
        }
    });
}
