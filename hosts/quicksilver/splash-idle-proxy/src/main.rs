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
    io,
    net::{Ipv4Addr, Ipv6Addr, SocketAddr},
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, Ordering},
    },
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use tokio::{
    io::{AsyncRead, AsyncReadExt},
    net::{TcpListener, TcpStream, UnixStream},
    process::Command,
    signal::unix::{SignalKind, signal},
    sync::{Notify, watch},
    time::{interval, sleep, timeout},
};

type Body = UnsyncBoxBody<Bytes, hyper::Error>;
type Err = Box<dyn Error + Send + Sync>;
static NEXT_REQUEST_ID: AtomicU64 = AtomicU64::new(1);

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
    log_requests: bool,
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

    async fn acquire(self: &Arc<Self>, request_id: Option<u64>) -> Result<Arc<Instance>, Err> {
        loop {
            let (c, mut state, stopping) = {
                let mut inner = self.inner.lock().unwrap();
                if inner.closing {
                    return Err("proxy shutting down".into());
                }
                let c = match &inner.child {
                    Some(c) => Arc::clone(c),
                    None => {
                        if let Some(id) = request_id {
                            eprintln!("wake ts_ms={} id={id}", unix_time_ms());
                        }
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

    async fn serve(self: Arc<Self>, req: Request<Incoming>, client: SocketAddr) -> Response<Body> {
        let passive = matches!(
            req.uri().path(),
            "/health" | "/ready" | "/status" | "/metrics"
        );
        let request_id = self.log_requests.then(|| {
            let id = NEXT_REQUEST_ID.fetch_add(1, Ordering::Relaxed);
            eprintln!("{}", request_log(&req, client, id, passive));
            id
        });
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
            match self.acquire(request_id).await {
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

fn unix_time_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
}

fn request_log<T>(req: &Request<T>, client: SocketAddr, id: u64, passive: bool) -> String {
    // Log only selected metadata, never the query, body, or credentials headers.
    let clip = |value: &str| value.chars().take(256).collect::<String>();
    let field = |name| {
        req.headers()
            .get(name)
            .and_then(|value| value.to_str().ok())
            .map(clip)
    };
    format!(
        "request ts_ms={} id={id} client={client} method={:?} path={:?} host={:?} user_agent={:?} passive={passive}",
        unix_time_ms(),
        clip(req.method().as_str()),
        clip(req.uri().path()),
        field(header::HOST),
        field(header::USER_AGENT),
    )
}

async fn read_proxy_source(stream: &mut (impl AsyncRead + Unpin)) -> io::Result<SocketAddr> {
    let invalid = || io::Error::new(io::ErrorKind::InvalidData, "invalid PROXY v2 TCP header");
    let mut header = [0; 16];
    stream.read_exact(&mut header).await?;
    if &header[..12] != b"\r\n\r\n\0\r\nQUIT\n" || header[12] != 0x21 {
        return Err(invalid());
    }
    // Serve sends a TCP address block without optional TLVs. Read exactly the
    // header bytes so the following HTTP request is untouched.
    match (header[13], u16::from_be_bytes([header[14], header[15]])) {
        (0x11, 12) => {
            let mut addr = [0; 12];
            stream.read_exact(&mut addr).await?;
            let ip = Ipv4Addr::new(addr[0], addr[1], addr[2], addr[3]);
            Ok((ip, u16::from_be_bytes([addr[8], addr[9]])).into())
        }
        (0x21, 36) => {
            let mut addr = [0; 36];
            stream.read_exact(&mut addr).await?;
            let ip = Ipv6Addr::from(*addr.first_chunk::<16>().unwrap());
            Ok((ip, u16::from_be_bytes([addr[32], addr[33]])).into())
        }
        _ => Err(invalid()),
    }
}

async fn accept_proxy(listener: Option<&TcpListener>) -> io::Result<(TcpStream, SocketAddr)> {
    match listener {
        Some(listener) => listener.accept().await,
        None => pending().await,
    }
}

async fn serve_connection(p: Arc<Proxy>, stream: TcpStream, client: SocketAddr) {
    let svc = service_fn(move |req| {
        let p = Arc::clone(&p);
        async move { Ok::<_, Infallible>(p.serve(req, client).await) }
    });
    let _ = hyper::server::conn::http1::Builder::new()
        .timer(TokioTimer::new())
        .header_read_timeout(Duration::from_secs(30))
        .half_close(false)
        .serve_connection(TokioIo::new(stream), svc)
        .await;
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
    let mut proxy_addr: Option<SocketAddr> = None;
    let mut idle = 600;
    let mut startup = 240;
    let mut log_requests = false;
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
        if arg == "--log-requests" {
            log_requests = true;
            continue;
        }
        let value = args.next().ok_or("missing option value")?;
        match arg.as_str() {
            "--listen" => addr = value,
            "--proxy-protocol-listen" => {
                let addr: SocketAddr = value.parse()?;
                if !addr.ip().is_loopback() {
                    return Err("--proxy-protocol-listen must use a loopback address".into());
                }
                proxy_addr = Some(addr);
            }
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
        return Err("usage: splash-idle-proxy [--listen ADDR] [--proxy-protocol-listen LOOPBACK_ADDR] [--idle SECONDS] [--startup SECONDS] [--allowed-host HOST] [--log-requests] -- splash serve [options]".into());
    }
    let p = Arc::new(Proxy {
        args,
        hosts,
        idle: Duration::from_secs(idle),
        startup: Duration::from_secs(startup),
        log_requests,
        inner: Mutex::new(Inner {
            child: None,
            active: 0,
            last_work: Instant::now(),
            closing: false,
        }),
    });
    let listener = TcpListener::bind(addr).await?;
    let proxy_listener = if let Some(addr) = proxy_addr {
        Some(TcpListener::bind(addr).await?)
    } else {
        None
    };
    eprintln!("listening on {}", listener.local_addr()?);
    if let Some(listener) = &proxy_listener {
        eprintln!("listening for PROXY v2 on {}", listener.local_addr()?);
    }
    let mut tick = interval(Duration::from_secs(1));
    let mut term = signal(SignalKind::terminate())?;
    let mut interrupt = signal(SignalKind::interrupt())?;
    loop {
        tokio::select! {
            _ = term.recv() => break,
            _ = interrupt.recv() => break,
            _ = tick.tick() => p.reap(),
            result = listener.accept() => {
                let (stream, peer) = result?;
                tokio::spawn(serve_connection(Arc::clone(&p), stream, peer));
            }
            result = accept_proxy(proxy_listener.as_ref()) => {
                let (mut stream, _) = result?;
                let this = Arc::clone(&p);
                tokio::spawn(async move {
                    if let Ok(Ok(client)) = timeout(Duration::from_secs(5), read_proxy_source(&mut stream)).await {
                        serve_connection(this, stream, client).await;
                    }
                });
            }
        }
    }
    drop(listener);
    drop(proxy_listener);
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
            log_requests: false,
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
    fn request_log_includes_routing_metadata_but_not_secrets() {
        let req = Request::builder()
            .method("POST")
            .uri("/v1/chat/completions?api_key=query-secret")
            .header(header::HOST, "quicksilver")
            .header(header::USER_AGENT, "test-client")
            .header(header::AUTHORIZATION, "Bearer auth-secret")
            .header(header::COOKIE, "token=cookie-secret")
            .body("body-secret")
            .unwrap();
        let line = request_log(&req, "127.0.0.1:1234".parse().unwrap(), 42, false);
        for expected in [
            "id=42",
            "client=127.0.0.1:1234",
            "method=\"POST\"",
            "path=\"/v1/chat/completions\"",
            "quicksilver",
            "test-client",
            "passive=false",
        ] {
            assert!(line.contains(expected), "{line}");
        }
        assert!(!line.contains("secret"), "{line}");
    }

    #[tokio::test]
    async fn proxy_v2_reads_ipv4_and_ipv6_without_consuming_http() {
        let http = b"GET /health HTTP/1.1\r\n";
        let mut v4 = b"\r\n\r\n\0\r\nQUIT\n\x21\x11\0\x0c".to_vec();
        v4.extend_from_slice(&[100, 64, 0, 1, 127, 0, 0, 1, 0x12, 0x34, 0x1f, 0x90]);
        let mut v6 = b"\r\n\r\n\0\r\nQUIT\n\x21\x21\0\x24".to_vec();
        v6.extend_from_slice(&"fd7a:115c:a1e0::1".parse::<Ipv6Addr>().unwrap().octets());
        v6.extend_from_slice(&Ipv6Addr::LOCALHOST.octets());
        v6.extend_from_slice(&[0x12, 0x34, 0x1f, 0x90]);
        for (mut header, expected) in [(v4, "100.64.0.1:4660"), (v6, "[fd7a:115c:a1e0::1]:4660")] {
            header.extend_from_slice(http);
            let mut stream = header.as_slice();
            assert_eq!(
                read_proxy_source(&mut stream).await.unwrap().to_string(),
                expected
            );
            assert_eq!(stream, http);
        }
        assert!(read_proxy_source(&mut http.as_slice()).await.is_err());
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
