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

struct JjUpstreamQuery {
    revision: String,
    template: String,
}

struct JjBookmarkHint {
    label: String,
    depth: u64,
}

impl JjUpstreamQuery {
    fn new(label: &str, current: &str) -> Self {
        // Labels already carry JSON escaping, which also quotes revset strings.
        // Prefer origin; multiple distinct other targets suppress both arrows.
        let targets = format!(
            "coalesce(tracked_remote_bookmarks(exact:\"{label}\", remote=exact:\"origin\"), tracked_remote_bookmarks(exact:\"{label}\"))"
        );
        // No upstream means comparing the working copy to itself, not all history.
        let comparison = format!("coalesce({targets}, {current})");
        let revision =
            format!("({targets}) | (({comparison})..{current}) | ({current}..({comparison}))");
        let targets = targets.replace('\\', "\\\\").replace('"', "\\\"");
        let upstream = comparison.replace('\\', "\\\\").replace('"', "\\\"");
        let template = format!(
            r#"concat("D|", if(self.contained_in("{targets}"), "T"), if(self.contained_in("({upstream})..{current}"), "A"), if(self.contained_in("{current}..({upstream})"), "B"), "\n")"#
        );
        Self { revision, template }
    }

    fn counts(output: &str) -> (usize, usize) {
        let markers: Vec<_> = output
            .lines()
            .filter_map(|line| line.strip_prefix("D|"))
            .flat_map(str::bytes)
            .collect();
        if markers.iter().filter(|&&c| c == b'T').count() == 1 {
            (
                markers.iter().filter(|&&c| c == b'A').count(),
                markers.iter().filter(|&&c| c == b'B').count(),
            )
        } else {
            (0, 0)
        }
    }
}

impl Request<'_> {
    fn command(&self, args: &[impl AsRef<OsStr>], status: bool) -> Command {
        let mut command = Command::new("git");
        command
            .args([OsStr::new("-C"), self.dir])
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .args(args)
            .envs(self.path.map(|path| ("PATH", path)));
        command.envs(self.git_env.iter().filter_map(|[name, value]| {
            (!status || name != b"GIT_OPTIONAL_LOCKS")
                .then(|| (OsStr::from_bytes(name), OsStr::from_bytes(value)))
        }));
        command
    }

    fn git(&self, args: &[impl AsRef<OsStr>]) -> Vec<u8> {
        let output = self.command(args, false).output();
        let mut bytes = output.map(|o| o.stdout).unwrap_or_default();
        // Match Zsh command substitution, which strips all trailing newlines.
        bytes.truncate(bytes.iter().rposition(|&c| c != b'\n').map_or(0, |i| i + 1));
        bytes
    }

    fn jj_root(&self) -> Option<PathBuf> {
        if self
            .git_env
            .iter()
            .any(|[n, _]| n == b"GIT_DIR" || n == b"GIT_WORK_TREE")
        {
            return None;
        }
        let mut dir = PathBuf::from(self.dir);
        loop {
            if dir.join(".jj").is_dir() {
                return Some(dir);
            }
            if dir.join(".git").exists() || !dir.pop() {
                return None;
            }
        }
    }

    fn jj_output(&self, revision: &str, template: &str, snapshot: bool) -> Option<Vec<u8>> {
        let mut command = Command::new("jj");
        command
            .current_dir(self.dir)
            .args(["--color=never", "--no-pager"])
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .envs(self.path.map(|p| ("PATH", p)));
        command.envs(
            self.git_env
                .iter()
                .map(|[n, v]| (OsStr::from_bytes(n), OsStr::from_bytes(v))),
        );
        if !snapshot {
            command.arg("--ignore-working-copy");
        }
        let output = command
            .args(["log", "--no-graph", "-r", revision, "-T", template])
            .output()
            .ok()?;
        output.status.success().then_some(output.stdout)
    }

    fn jj_status(
        &self,
        result: &mut Vec<u8>,
        bookmark_hint: &mut Option<JjBookmarkHint>,
    ) -> Option<()> {
        // Names are escaped before entering the line-oriented wire protocol.
        const GRAPH: &str = r#"concat(commit_id, "|", parents.map(|p| p.commit_id()).join(" "), "|", local_bookmarks.map(|b| b.name().escape_json()).join("\t"), "\n")"#;
        // Snapshot once and return metadata plus the first ancestry window together.
        // Without an ancestral bookmark, only @ is needed for the change-ID fallback.
        let mut template = format!(
            r#"if(current_working_copy, concat("M|", commit_id, "|", change_id.short(8), "|", self.contained_in("bookmarks()::"), "|", diff.files().map(|f| f.status_char()).join(""), "|", conflicted_files.len(), "\n")) ++ {GRAPH}"#
        );
        // Reuse the successful search size as well as the name. Deep bookmarks
        // should not require the same sequence of expanding queries every time.
        let mut depth = bookmark_hint.as_ref().map_or(16, |hint| hint.depth);
        let window = format!("ancestors(@, {depth}) & (bookmarks():: | @)");
        let predicted = bookmark_hint
            .as_ref()
            .map(|hint| JjUpstreamQuery::new(&hint.label, "@"));
        let revision = if let Some(query) = &predicted {
            // Cache only the query plan. All status is recomputed after snapshotting,
            // and the hint is verified by the fresh closest-bookmark search below.
            template = format!(
                r#"if(self.contained_in("{window}"), {template}) ++ {}"#,
                query.template
            );
            format!("({window}) | ({})", query.revision)
        } else {
            window
        };
        let initial = self.jj_output(&revision, &template, true)?;
        let initial = str::from_utf8(&initial).ok()?;
        let metadata = initial.lines().find_map(|line| line.strip_prefix("M|"))?;
        let fields: Vec<_> = metadata.split('|').collect();
        if fields.len() < 5 {
            return None;
        }
        let mut label = fields[1].to_owned();
        let mut bookmark = false;
        if fields[2] == "true" {
            let initial_depth = depth;
            loop {
                let expanded;
                let graph = if depth == initial_depth {
                    initial
                } else {
                    expanded = self.jj_output(
                        &format!("ancestors({}, {depth})", fields[0]),
                        GRAPH,
                        false,
                    )?;
                    str::from_utf8(&expanded).ok()?
                };
                let nodes: std::collections::HashMap<_, _> = graph
                    .lines()
                    .filter(|line| !line.starts_with("M|") && !line.starts_with("D|"))
                    .filter_map(|line| {
                        let mut parts = line.splitn(3, '|');
                        Some((parts.next()?, (parts.next()?, parts.next()?)))
                    })
                    .collect();
                let mut frontier = vec![fields[0]];
                let mut visited = std::collections::HashSet::new();
                let mut found = None;
                let mut generations = 1u64;
                while !frontier.is_empty() {
                    let mut names = Vec::new();
                    let mut next = Vec::new();
                    for id in frontier {
                        if !visited.insert(id) {
                            continue;
                        }
                        if let Some((parents, bookmarks)) = nodes.get(id) {
                            names.extend(bookmarks.split('\t').filter(|n| !n.is_empty()));
                            next.extend(parents.split_whitespace());
                        }
                    }
                    if let Some(name) = names.into_iter().min() {
                        found = Some(
                            name.strip_prefix('"')
                                .and_then(|s| s.strip_suffix('"'))
                                .unwrap_or(name)
                                .to_owned(),
                        );
                        break;
                    }
                    frontier = next;
                    generations = generations.checked_add(1)?;
                }
                if let Some(name) = found {
                    label = name;
                    bookmark = true;
                    // Shrink again after moving nearer a bookmark or changing
                    // repositories, retaining headroom for ordinary jj new steps.
                    depth = generations.checked_next_power_of_two()?.max(16);
                    break;
                }
                // Bookmarks can disappear concurrently; terminate once the graph is complete.
                if nodes
                    .values()
                    .all(|(p, _)| p.split_whitespace().all(|id| nodes.contains_key(id)))
                {
                    break;
                }
                // Expand faster on misses to reduce process launches for distant
                // bookmarks. Successful searches still shrink to a power of two.
                depth = depth.checked_mul(4)?;
            }
        }
        let mut ahead = 0;
        let mut behind = 0;
        if bookmark {
            if bookmark_hint.as_ref().map(|hint| &hint.label) == Some(&label) {
                (ahead, behind) = JjUpstreamQuery::counts(initial);
            } else {
                let query = JjUpstreamQuery::new(&label, fields[0]);
                if let Some(counts) = self.jj_output(&query.revision, &query.template, false) {
                    (ahead, behind) = JjUpstreamQuery::counts(str::from_utf8(&counts).ok()?);
                }
            }
        }
        *bookmark_hint = bookmark.then(|| JjBookmarkHint {
            label: label.clone(),
            depth,
        });
        let mut counts = [0u64; 3];
        for status in fields[3].bytes() {
            match status {
                b'A' => counts[0] += 1,
                b'D' => counts[2] += 1,
                _ => counts[1] += 1,
            }
        }
        write!(
            result,
            "jj\x1f{}\x1f{}\x1f{}\x1f{}\x1f{}\x1f{}\x1f{}\x1f{}",
            label,
            fields[1],
            counts[0],
            counts[1],
            counts[2],
            number(fields[4].as_bytes()),
            ahead,
            behind
        )
        .ok()?;
        Some(())
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
            .find_map(|(file, kind)| {
                dir.push(file);
                let found = dir.metadata().is_ok_and(|m| kind != "rebase" || m.is_dir());
                dir.pop();
                found.then_some(kind.as_bytes())
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
        result.extend_from_slice(tags.rsplit(|&c| c == b'\n').next().unwrap_or_default());
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
        .filter(|(name, _)| {
            name.as_bytes().starts_with(b"GIT_") || name.as_bytes().starts_with(b"JJ_")
        })
        .for_each(|(name, _)| env::remove_var(name));
    let inherited_path = env::var_os("PATH");
    let mut input = io::stdin().lock();
    let mut output = io::stdout().lock();
    let mut result = Vec::with_capacity(256);
    // Reuse request fields, the status line and header values across requests.
    let mut fields: [_; 4] = Default::default();
    let mut git_env: Vec<[Vec<u8>; 2]> = Vec::new();
    let mut buffers = Default::default();
    // Keep query plans for recently visited repositories, shared by their
    // subdirectories. Every plan is still verified against freshly queried data.
    let mut jj_bookmark_hints: Vec<(PathBuf, Option<JjBookmarkHint>)> = Vec::new();
    loop {
        read_fields(&mut input, &mut fields)?;
        let [id, dir, path, count] = &fields;
        git_env.resize_with(number(count) as usize, Default::default);
        for pair in &mut git_env {
            read_fields(&mut input, pair)?;
            if !pair[0].starts_with(b"GIT_") && !pair[0].starts_with(b"JJ_") {
                std::process::exit(1);
            }
        }
        let path = OsStr::from_bytes(path);
        let request = Request {
            dir: OsStr::from_bytes(dir),
            path: (inherited_path.as_deref() != Some(path)).then_some(path),
            git_env: &git_env,
        };
        result.clone_from(id);
        result.push(b':');
        let start = result.len();
        let status = if let Some(root) = request.jj_root() {
            let mut entry = jj_bookmark_hints
                .iter()
                .position(|(dir, _)| dir == &root)
                .map(|index| jj_bookmark_hints.remove(index))
                .unwrap_or((root, None));
            let status = request.jj_status(&mut result, &mut entry.1);
            // Bound memory in long-lived shells, evicting the least recently used.
            if jj_bookmark_hints.len() == 32 {
                jj_bookmark_hints.remove(0);
            }
            jj_bookmark_hints.push(entry);
            status
        } else {
            request.status(&mut result, &mut buffers)
        };
        if status.is_none() {
            result.truncate(start);
        }
        result.push(b'\n');
        output.write_all(&result)?;
        output.flush()?;
    }
}

fn main() {
    if let Err(error) = run() {
        if ![io::ErrorKind::BrokenPipe, io::ErrorKind::UnexpectedEof].contains(&error.kind()) {
            eprintln!("git status daemon: {error}");
            std::process::exit(1);
        }
    }
}
