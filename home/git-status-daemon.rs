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
    fn command<S: AsRef<OsStr>>(&self, args: &[S]) -> Command {
        let mut command = Command::new("git");
        command
            .arg("-C")
            .arg(self.dir)
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .args(args);
        // Leaving an unchanged PATH inherited avoids rebuilding the entire
        // environment for auxiliary commands with no Git overrides.
        if let Some(path) = &self.path {
            command.env("PATH", path);
        }
        for [name, value] in self.git_env {
            command.env(OsStr::from_bytes(name), OsStr::from_bytes(value));
        }
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

    fn status(&self, result: &mut Vec<u8>) -> Option<()> {
        let mut child = self
            .command(&["status", "--porcelain=v2", "--branch", "--show-stash"])
            .env("GIT_OPTIONAL_LOCKS", "0")
            .stdout(Stdio::piped())
            .spawn()
            .ok()?;
        let mut porcelain = io::BufReader::with_capacity(4096, child.stdout.take()?);
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
            let mut remote =
                self.git(&[b"config".as_slice(), b"--get", &key].map(OsStr::from_bytes));
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
                .find_map(|(file, action)| dir.join(file).exists().then_some(action.as_bytes()))
                .unwrap_or_default()
            };
        }
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
        Some(())
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
    let mut output = io::stdout().lock();
    let mut result = Vec::with_capacity(256);
    // Reuse raw field buffers across requests; Git commands borrow their bytes.
    let mut fields = std::array::from_fn(|_| Vec::new());
    let mut git_env = Vec::new();
    while read_fields(&mut input, &mut fields)? {
        let [id, dir, path, count] = &fields;
        let count = number(count);
        for index in 0..count {
            if index == git_env.len() as u64 {
                git_env.push([Vec::new(), Vec::new()]);
            }
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
        let _ = request.status(&mut result);
        result.push(b'\n');
        output.write_all(&result)?;
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
