//! ddcd - localhost DDC brightness control for the RemindWall kiosk.
//!
//! The sandboxed Mac Catalyst app (TestFlight requires App Sandbox, which kills
//! both posix_spawn of Homebrew binaries AND IOKit DDC access) talks to this
//! daemon over 127.0.0.1 instead. The daemon shells out to m1ddc with a hard
//! per-call timeout and a mutex so DDC/I2C transactions never interleave -
//! the two failure modes a bare NSUserUnixTask path couldn't handle.
//!
//! Security model: this box also serves public traffic (hotchkiss.io), so
//! localhost is NOT a trust boundary. Every request must carry the `x-ddcd`
//! header - browsers can't attach custom headers cross-origin without a CORS
//! preflight, and we reject preflights (OPTIONS) outright, so browser-based
//! CSRF is structurally impossible. Requests bearing an Origin header are
//! refused for the same reason.

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use axum::body::Body;
use axum::extract::State;
use axum::http::{HeaderMap, Method, Request, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use tokio::process::Command;
use tokio::sync::Mutex;

/// Header every caller must set. The value is irrelevant; presence is the gate.
pub const GUARD_HEADER: &str = "x-ddcd";

/// Sanity bounds for DDC max luminance. Real monitors report ~100; a value
/// like 25600 means a byte-offset bug in the m1ddc build (shipped in HEAD
/// builds Apr 2025 - Jun 2026) and every computed brightness would be garbage.
const MAX_LUMINANCE_RANGE: std::ops::RangeInclusive<i64> = 1..=1000;

#[derive(Clone)]
pub struct Config {
    pub m1ddc_path: PathBuf,
    pub timeout: Duration,
    pub retry_delays: Vec<Duration>,
}

impl Config {
    /// Locates m1ddc in the standard Homebrew locations.
    pub fn from_env() -> Self {
        let m1ddc_path = std::env::var("DDCD_M1DDC")
            .map(PathBuf::from)
            .unwrap_or_else(|_| {
                ["/opt/homebrew/bin/m1ddc", "/usr/local/bin/m1ddc"]
                    .iter()
                    .map(PathBuf::from)
                    .find(|p| p.exists())
                    .unwrap_or_else(|| PathBuf::from("/opt/homebrew/bin/m1ddc"))
            });
        let timeout_ms = std::env::var("DDCD_TIMEOUT_MS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(5_000u64);
        Self {
            m1ddc_path,
            timeout: Duration::from_millis(timeout_ms),
            retry_delays: Self::default_retry_delays(),
        }
    }

    pub fn default_retry_delays() -> Vec<Duration> {
        vec![Duration::from_millis(300), Duration::from_millis(900)]
    }
}

#[derive(Debug)]
pub enum DdcError {
    /// m1ddc didn't answer within the timeout - a wedged I2C transaction.
    /// The child is killed (kill_on_drop), so it can't accumulate.
    Timeout,
    /// The binary is missing/not executable.
    Unavailable(String),
    /// m1ddc ran and failed. Note m1ddc prints errors to STDOUT, not stderr.
    Failed(String),
    /// Output that doesn't parse, or a max luminance outside sane bounds.
    BadOutput(String),
}

impl IntoResponse for DdcError {
    fn into_response(self) -> Response {
        let (status, msg) = match self {
            DdcError::Timeout => (StatusCode::GATEWAY_TIMEOUT, "m1ddc timed out (wedged DDC transaction?)".to_string()),
            DdcError::Unavailable(m) => (StatusCode::SERVICE_UNAVAILABLE, m),
            DdcError::Failed(m) => (StatusCode::BAD_GATEWAY, m),
            DdcError::BadOutput(m) => (StatusCode::BAD_GATEWAY, m),
        };
        tracing::warn!(%msg, "ddc operation failed");
        (status, Json(serde_json::json!({ "error": msg }))).into_response()
    }
}

/// Serialized, timeout-guarded m1ddc invocations. DDC/I2C is a single-master
/// bus; concurrent transactions corrupt each other.
pub struct Ddc {
    path: PathBuf,
    timeout: Duration,
    lock: Mutex<()>,
    /// Max luminance survives for the daemon's lifetime (it's a monitor
    /// property) - re-reading it doubled the DDC traffic of every operation.
    /// Invalidated when an operation fails, so a monitor swap heals itself.
    max_cache: Mutex<Option<i64>>,
    /// Backoff schedule for transient failures - the DCP AV service takes a
    /// few seconds to return after display wake, and a restore issued right
    /// after wake shouldn't fail spuriously. Timeouts are NOT retried (a
    /// wedged transaction already cost its full timeout).
    retry_delays: Vec<Duration>,
}

impl Ddc {
    pub fn new(config: &Config) -> Self {
        Self {
            path: config.m1ddc_path.clone(),
            timeout: config.timeout,
            lock: Mutex::new(()),
            max_cache: Mutex::new(None),
            retry_delays: config.retry_delays.clone(),
        }
    }

    pub fn binary_present(&self) -> bool {
        self.path.exists()
    }

    async fn run(&self, args: &[&str]) -> Result<String, DdcError> {
        let _guard = self.lock.lock().await;

        let child = Command::new(&self.path)
            .args(args)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .kill_on_drop(true)
            .spawn()
            .map_err(|e| DdcError::Unavailable(format!("cannot spawn {}: {e}", self.path.display())))?;

        let output = match tokio::time::timeout(self.timeout, child.wait_with_output()).await {
            // Dropping the future kills the child via kill_on_drop.
            Err(_) => return Err(DdcError::Timeout),
            Ok(Err(e)) => return Err(DdcError::Failed(format!("wait failed: {e}"))),
            Ok(Ok(output)) => output,
        };

        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            return Err(DdcError::Failed(format!(
                "m1ddc {} exited {}: {stdout} {stderr}",
                args.join(" "),
                output.status.code().map_or("signal".to_string(), |c| c.to_string()),
            )));
        }
        Ok(stdout)
    }

    /// Bounded retry for transient failures (panel wake, marginal DDC read).
    /// Retries only `Failed`/`BadOutput` — a `Timeout` already burned its full
    /// budget on a wedged transaction, and `Unavailable` won't heal by waiting.
    async fn run_with_retry(&self, args: &[&str]) -> Result<String, DdcError> {
        let mut last_err = None;
        for (attempt, delay) in std::iter::once(None)
            .chain(self.retry_delays.iter().map(Some))
            .enumerate()
        {
            if let Some(delay) = delay {
                tokio::time::sleep(*delay).await;
            }
            match self.run(args).await {
                Ok(out) => return Ok(out),
                Err(e @ (DdcError::Timeout | DdcError::Unavailable(_))) => return Err(e),
                Err(e) => {
                    tracing::warn!(args = args.join(" "), attempt, error = ?e, "ddc attempt failed");
                    last_err = Some(e);
                }
            }
        }
        Err(last_err.expect("at least one attempt ran"))
    }

    /// Reads a numeric value, retrying attempts whose output fails the
    /// plausibility check. DDC reads on flaky panels (LG especially) return
    /// corrupted values without any checksum protection — the kiosk's monitor
    /// has produced `luminance -51 / max 62` in the field. A corrupted read
    /// is a transient failure, not an answer.
    async fn read_validated(
        &self,
        args: &[&str],
        valid: impl Fn(i64) -> bool,
    ) -> Result<i64, DdcError> {
        let mut last_err = None;
        for (attempt, delay) in std::iter::once(None)
            .chain(self.retry_delays.iter().map(Some))
            .enumerate()
        {
            if let Some(delay) = delay {
                tokio::time::sleep(*delay).await;
            }
            match self.run(args).await {
                Ok(out) => match out.parse::<i64>() {
                    Ok(value) if valid(value) => return Ok(value),
                    Ok(value) => {
                        tracing::warn!(args = args.join(" "), attempt, value, "implausible DDC read");
                        last_err = Some(DdcError::BadOutput(format!(
                            "m1ddc {} returned implausible value {value} (corrupted DDC read?)",
                            args.join(" ")
                        )));
                    }
                    Err(_) => {
                        last_err = Some(DdcError::BadOutput(format!(
                            "m1ddc {} returned non-numeric: {out:?}",
                            args.join(" ")
                        )));
                    }
                },
                Err(e @ (DdcError::Timeout | DdcError::Unavailable(_))) => return Err(e),
                Err(e) => {
                    tracing::warn!(args = args.join(" "), attempt, error = ?e, "ddc attempt failed");
                    last_err = Some(e);
                }
            }
        }
        Err(last_err.expect("at least one attempt ran"))
    }

    /// Cached for the daemon's lifetime; see `max_cache`.
    pub async fn max_luminance(&self) -> Result<i64, DdcError> {
        if let Some(max) = *self.max_cache.lock().await {
            return Ok(max);
        }
        let max = self
            .read_validated(&["max", "luminance"], |v| MAX_LUMINANCE_RANGE.contains(&v))
            .await?;
        *self.max_cache.lock().await = Some(max);
        tracing::info!(max, "cached max luminance");
        Ok(max)
    }

    async fn invalidate_max(&self) {
        *self.max_cache.lock().await = None;
    }

    /// `max` bounds the plausibility check — a current reading outside
    /// 0..=max is a corrupted read, never a real panel state.
    pub async fn get_luminance(&self, max: i64) -> Result<i64, DdcError> {
        let result = self
            .read_validated(&["get", "luminance"], |v| (0..=max).contains(&v))
            .await;
        if result.is_err() {
            // The monitor may have changed (or gone away) - don't trust the
            // cached max on the next operation.
            self.invalidate_max().await;
        }
        result
    }

    pub async fn set_luminance(&self, value: i64) -> Result<(), DdcError> {
        let result = self.run_with_retry(&["set", "luminance", &value.to_string()]).await;
        if result.is_err() {
            self.invalidate_max().await;
        }
        result.map(|_| ())
    }
}

pub struct AppState {
    pub ddc: Ddc,
}

pub fn app(config: Config) -> Router {
    let state = Arc::new(AppState {
        ddc: Ddc::new(&config),
    });

    Router::new()
        .route("/health", get(health))
        .route("/brightness", get(get_brightness).put(put_brightness))
        .layer(middleware::from_fn(guard))
        .with_state(state)
}

/// The CSRF/SSRF gate - see module docs.
async fn guard(request: Request<Body>, next: Next) -> Response {
    if request.method() == Method::OPTIONS {
        return StatusCode::METHOD_NOT_ALLOWED.into_response();
    }
    if has_origin(request.headers()) {
        return (StatusCode::FORBIDDEN, "cross-origin requests are refused").into_response();
    }
    if request.headers().get(GUARD_HEADER).is_none() {
        return (StatusCode::FORBIDDEN, "missing x-ddcd header").into_response();
    }
    next.run(request).await
}

fn has_origin(headers: &HeaderMap) -> bool {
    headers.get(axum::http::header::ORIGIN).is_some()
}

#[derive(Serialize)]
struct Health {
    status: &'static str,
    m1ddc_present: bool,
}

async fn health(State(state): State<Arc<AppState>>) -> Json<Health> {
    Json(Health {
        status: "ok",
        m1ddc_present: state.ddc.binary_present(),
    })
}

#[derive(Serialize)]
struct Brightness {
    brightness: f64,
    raw: i64,
    max: i64,
}

async fn get_brightness(State(state): State<Arc<AppState>>) -> Result<Json<Brightness>, DdcError> {
    let max = state.ddc.max_luminance().await?;
    let raw = state.ddc.get_luminance(max).await?;
    Ok(Json(Brightness {
        brightness: (raw as f64 / max as f64).clamp(0.0, 1.0),
        raw,
        max,
    }))
}

#[derive(Deserialize)]
struct SetBrightness {
    brightness: f64,
}

async fn put_brightness(
    State(state): State<Arc<AppState>>,
    Json(body): Json<SetBrightness>,
) -> Result<StatusCode, Response> {
    if !(0.0..=1.0).contains(&body.brightness) || !body.brightness.is_finite() {
        return Err((
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(serde_json::json!({ "error": "brightness must be within 0.0...1.0" })),
        )
            .into_response());
    }

    let max = state.ddc.max_luminance().await.map_err(IntoResponse::into_response)?;
    let target = (body.brightness * max as f64).round() as i64;
    state
        .ddc
        .set_luminance(target)
        .await
        .map_err(IntoResponse::into_response)?;

    tracing::info!(brightness = body.brightness, target, max, "set luminance");
    Ok(StatusCode::NO_CONTENT)
}
