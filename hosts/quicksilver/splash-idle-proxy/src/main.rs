use http_body_util::{BodyExt, Full, combinators::UnsyncBoxBody};
use hyper::{
    Request, Response, StatusCode, Uri,
    body::{Bytes, Incoming},
    header,
    service::service_fn,
};
use hyper_util::rt::{TokioIo, TokioTimer};
use std::{
    collections::HashSet,
    convert::Infallible,
    error::Error,
    future::pending,
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
use tokio::{
    net::{TcpListener, UnixStream},
    process::Command,
    signal::unix::{SignalKind, signal},
    sync::{Notify, watch},
    time::{interval, sleep, timeout},
};

type Body = UnsyncBoxBody<Bytes, hyper::Error>;
type Err = Box<dyn Error + Send + Sync>;

#[derive(Clone, Copy, PartialEq, Eq)]
enum State {
    Starting,
    Ready,
    Stopping,
    Exited,
}

struct Instance {
    socket: PathBuf,
    state: watch::Sender<State>,
    stop: Notify,
}

struct Inner {
    child: Option<Arc<Instance>>,
    active: usize,
    last_work: Instant,
    closing: bool,
}

struct Proxy {
    args: Vec<String>,
    hosts: HashSet<String>,
    idle: Duration,
    startup: Duration,
    inner: Mutex<Inner>,
}

struct Work(Arc<Proxy>);

impl Drop for Work {
    fn drop(&mut self) {
        let mut inner = self.0.inner.lock().unwrap();
        inner.active -= 1;
        inner.last_work = Instant::now();
    }
}

impl Instance {
    fn stop(&self) {
        let changed = self.state.send_if_modified(|state| {
            if matches!(state, State::Stopping | State::Exited) {
                return false;
            }
            *state = State::Stopping;
            true
        });
        if changed {
            self.stop.notify_one();
        }
    }
}

impl Proxy {
    // Called with the lifecycle lock held, so simultaneous requests share one start.
    fn start(self: &Arc<Self>) -> Result<Arc<Instance>, Err> {
        // macOS limits Unix socket paths to 104 bytes. Keep the path short and private.
        let dir = tempfile::Builder::new()
            .prefix("splash-idle-")
            .tempdir_in("/tmp")?;
        let socket = dir.path().join("http.sock");
        let mut child = Command::new(&self.args[0])
            .args(&self.args[1..])
            .arg("--host")
            .arg(format!("unix:{}", socket.display()))
            // Splash watches this PID and stops if the proxy dies unexpectedly.
            .env("SPLASH_APP_PID", std::process::id().to_string())
            .kill_on_drop(true)
            .spawn()?;
        let instance = Arc::new(Instance {
            socket,
            state: watch::channel(State::Starting).0,
            stop: Notify::new(),
        });
        let this = Arc::clone(self);
        let c = Arc::clone(&instance);
        eprintln!("starting Splash (pid {:?})", child.id());
        tokio::spawn(async move {
            let ready = async {
                // Splash binds early but does not listen until the runtime is ready.
                while UnixStream::connect(&c.socket).await.is_err() {
                    sleep(Duration::from_millis(250)).await;
                }
            };
            let warmup = async {
                if timeout(this.startup, ready).await.is_err() {
                    eprintln!("Splash did not become ready before the startup deadline");
                    let _inner = this.inner.lock().unwrap();
                    c.stop();
                    return;
                }
                c.state.send_if_modified(|state| {
                    if *state != State::Starting {
                        return false;
                    }
                    *state = State::Ready;
                    true
                });
                pending::<()>().await;
            };
            let status = tokio::select! {
                status = child.wait() => status,
                _ = c.stop.notified() => terminate(&mut child).await,
                _ = warmup => terminate(&mut child).await,
            };
            drop(dir);
            let mut inner = this.inner.lock().unwrap();
            inner.child = None;
            c.state.send_replace(State::Exited);
            eprintln!("Splash exited: {status:?}");
        });
        Ok(instance)
    }

    async fn acquire(self: &Arc<Self>) -> Result<Arc<Instance>, Err> {
        loop {
            let (c, mut state, stopping) = {
                let mut inner = self.inner.lock().unwrap();
                if inner.closing {
                    return Err("proxy shutting down".into());
                }
                let c = match &inner.child {
                    Some(c) => Arc::clone(c),
                    None => {
                        let c = self.start()?;
                        inner.child = Some(Arc::clone(&c));
                        c
                    }
                };
                let state = c.state.subscribe();
                let stopping = *state.borrow() == State::Stopping;
                (c, state, stopping)
            };
            if stopping {
                state.wait_for(|s| *s == State::Exited).await?;
                continue;
            }
            if *state.wait_for(|s| *s != State::Starting).await? == State::Ready {
                return Ok(c);
            }
            return Err("Splash exited or timed out before becoming ready".into());
        }
    }

    fn reap(&self) {
        let inner = self.inner.lock().unwrap();
        if inner.active == 0
            && inner.last_work.elapsed() >= self.idle
            && let Some(c) = &inner.child
        {
            let stopping = *c.state.borrow() == State::Stopping;
            if !stopping {
                eprintln!("Splash idle; stopping to release memory");
                c.stop();
            }
        }
    }

    async fn serve(self: Arc<Self>, req: Request<Incoming>) -> Response<Body> {
        let host = req
            .headers()
            .get(header::HOST)
            .and_then(|host| host.to_str().ok())
            .and_then(|host| host.parse::<hyper::http::uri::Authority>().ok());
        if !host.is_some_and(|host| {
            self.hosts.contains(
                &host
                    .host()
                    .trim_matches(['[', ']'])
                    .trim_end_matches('.')
                    .to_ascii_lowercase(),
            )
        }) {
            return reply(StatusCode::BAD_REQUEST, "unrecognized Host", None);
        }
        let passive = matches!(
            req.uri().path(),
            "/health" | "/ready" | "/status" | "/metrics"
        );
        let (c, work) = if passive {
            let child = self.inner.lock().unwrap().child.clone();
            match child {
                Some(c) if *c.state.borrow() == State::Ready => (c, None),
                _ if req.uri().path() == "/health" => {
                    return reply(
                        StatusCode::OK,
                        r#"{"status":"ok","backend_ready":false}"#,
                        Some("application/json"),
                    );
                }
                _ => {
                    return reply(
                        StatusCode::SERVICE_UNAVAILABLE,
                        r#"{"status":"unavailable","backend_ready":false}"#,
                        Some("application/json"),
                    );
                }
            }
        } else {
            {
                let mut inner = self.inner.lock().unwrap();
                if inner.active >= 32 {
                    return reply(
                        StatusCode::SERVICE_UNAVAILABLE,
                        "Splash proxy is busy",
                        None,
                    );
                }
                inner.active += 1;
            }
            let work = Work(Arc::clone(&self));
            match self.acquire().await {
                Ok(c) => (c, Some(work)),
                Err(e) => {
                    eprintln!("cannot start Splash: {e}");
                    return reply(StatusCode::SERVICE_UNAVAILABLE, "Splash unavailable", None);
                }
            }
        };
        match forward(&c.socket, req, work).await {
            Ok(resp) => resp,
            Err(e) => {
                eprintln!("Splash request failed: {e}");
                reply(StatusCode::BAD_GATEWAY, "Splash unavailable", None)
            }
        }
    }
}

async fn terminate(child: &mut tokio::process::Child) -> std::io::Result<std::process::ExitStatus> {
    if let Some(pid) = child.id() {
        // SAFETY: the PID belongs to this child, which we have not reaped.
        unsafe { libc::kill(pid as libc::pid_t, libc::SIGTERM) };
    }
    match timeout(Duration::from_secs(15), child.wait()).await {
        Ok(status) => status,
        Err(_) => {
            child.start_kill()?;
            child.wait().await
        }
    }
}

fn strip_hop_headers(headers: &mut header::HeaderMap) {
    let connection_headers: Vec<_> = headers
        .get_all(header::CONNECTION)
        .iter()
        .filter_map(|v| v.to_str().ok())
        .flat_map(|v| v.split(','))
        .filter_map(|v| header::HeaderName::from_bytes(v.trim().as_bytes()).ok())
        .collect();
    for name in connection_headers {
        headers.remove(name);
    }
    for name in [
        "connection",
        "keep-alive",
        "proxy-connection",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailer",
        "transfer-encoding",
        "upgrade",
    ] {
        headers.remove(name);
    }
}

async fn forward(
    socket: &Path,
    mut req: Request<Incoming>,
    work: Option<Work>,
) -> Result<Response<Body>, Err> {
    // Keep the original Host/Origin; Splash validates them and handles API auth.
    let host = req.headers().get(header::HOST).cloned();
    strip_hop_headers(req.headers_mut());
    if let Some(host) = host {
        req.headers_mut().insert(header::HOST, host);
    }
    for name in [
        "forwarded",
        "x-forwarded-for",
        "x-forwarded-host",
        "x-forwarded-proto",
    ] {
        req.headers_mut().remove(name);
    }
    *req.uri_mut() = req
        .uri()
        .path_and_query()
        .map_or("/", |p| p.as_str())
        .parse::<Uri>()?;
    // Each request gets a Unix connection; do not pool connections to a stopped child.
    let io = TokioIo::new(UnixStream::connect(socket).await?);
    let (mut sender, conn) = hyper::client::conn::http1::handshake(io).await?;
    tokio::spawn(async move {
        let _ = conn.await;
    });
    let mut resp = sender.send_request(req).await?;
    strip_hop_headers(resp.headers_mut());
    // Hyper forwards frames without buffering. Keep the idle guard until the
    // downstream finishes the body or disconnects, not just until SSE headers.
    Ok(resp.map(|body| {
        body.map_frame(move |frame| {
            let _ = &work;
            frame
        })
        .boxed_unsync()
    }))
}

fn reply(status: StatusCode, text: &'static str, content_type: Option<&str>) -> Response<Body> {
    Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, content_type.unwrap_or("text/plain"))
        .body(
            Full::new(Bytes::from_static(text.as_bytes()))
                .map_err(|e| match e {})
                .boxed_unsync(),
        )
        .unwrap()
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), Err> {
    let mut addr = "127.0.0.1:8080".to_owned();
    let mut idle = 600;
    let mut startup = 240;
    let mut hosts = HashSet::from([
        "localhost".to_owned(),
        "127.0.0.1".to_owned(),
        "::1".to_owned(),
    ]);
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        if arg == "--" {
            break;
        }
        let value = args.next().ok_or("missing option value")?;
        match arg.as_str() {
            "--listen" => addr = value,
            "--idle" => idle = value.parse()?,
            "--startup" => startup = value.parse()?,
            "--allowed-host" => {
                hosts.insert(value.trim_end_matches('.').to_ascii_lowercase());
            }
            _ => return Err(format!("unknown option {arg}").into()),
        }
    }
    let args: Vec<_> = args.collect();
    if args.is_empty() || idle == 0 || startup == 0 {
        return Err("usage: splash-idle-proxy [--listen ADDR] [--idle SECONDS] [--startup SECONDS] [--allowed-host HOST] -- splash serve [options]".into());
    }
    let p = Arc::new(Proxy {
        args,
        hosts,
        idle: Duration::from_secs(idle),
        startup: Duration::from_secs(startup),
        inner: Mutex::new(Inner {
            child: None,
            active: 0,
            last_work: Instant::now(),
            closing: false,
        }),
    });
    let listener = TcpListener::bind(addr).await?;
    eprintln!("listening on {}", listener.local_addr()?);
    let mut tick = interval(Duration::from_secs(1));
    let mut term = signal(SignalKind::terminate())?;
    let mut interrupt = signal(SignalKind::interrupt())?;
    loop {
        tokio::select! {
            _ = term.recv() => break,
            _ = interrupt.recv() => break,
            _ = tick.tick() => p.reap(),
            result = listener.accept() => {
                let (stream, _) = result?;
                let this = Arc::clone(&p);
                tokio::spawn(async move {
                    let svc = service_fn(move |req| {
                        let p = Arc::clone(&this);
                        async move { Ok::<_, Infallible>(p.serve(req).await) }
                    });
                    let _ = hyper::server::conn::http1::Builder::new()
                        .timer(TokioTimer::new()).header_read_timeout(Duration::from_secs(30))
                        .half_close(false).serve_connection(TokioIo::new(stream), svc).await;
                });
            }
        }
    }
    drop(listener);
    let c = {
        let mut inner = p.inner.lock().unwrap();
        inner.closing = true;
        inner.child.clone()
    };
    if let Some(c) = c {
        c.stop();
        let _ = c.state.subscribe().wait_for(|s| *s == State::Exited).await;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn idle_reaper_waits_for_active_work() {
        let instance = Arc::new(Instance {
            socket: PathBuf::new(),
            state: watch::channel(State::Ready).0,
            stop: Notify::new(),
        });
        let idle = Duration::from_secs(10);
        let proxy = Arc::new(Proxy {
            args: Vec::new(),
            hosts: HashSet::new(),
            idle,
            startup: Duration::from_secs(240),
            inner: Mutex::new(Inner {
                child: Some(Arc::clone(&instance)),
                active: 1,
                last_work: Instant::now() - idle,
                closing: false,
            }),
        });
        let work = Work(Arc::clone(&proxy));
        proxy.reap();
        assert!(*instance.state.borrow() == State::Ready);
        drop(work);
        proxy.reap();
        assert!(*instance.state.borrow() == State::Ready);
        proxy.inner.lock().unwrap().last_work = Instant::now() - idle;
        proxy.reap();
        assert!(*instance.state.borrow() == State::Stopping);
        instance.state.send_replace(State::Exited);
        instance.stop();
        assert!(*instance.state.borrow() == State::Exited);
    }

    #[test]
    fn strips_connection_scoped_headers_but_keeps_stream_headers() {
        let mut headers = header::HeaderMap::new();
        headers.append(header::CONNECTION, "close, X-Temporary".parse().unwrap());
        headers.insert("x-temporary", "remove".parse().unwrap());
        headers.insert(header::TRANSFER_ENCODING, "chunked".parse().unwrap());
        headers.insert(header::CONTENT_TYPE, "text/event-stream".parse().unwrap());
        strip_hop_headers(&mut headers);
        assert_eq!(headers.len(), 1);
        assert_eq!(headers[header::CONTENT_TYPE], "text/event-stream");
    }
}
