//! Integration tests against a fake m1ddc so no hardware (or Homebrew) is
//! needed. The fake is a shell script the test writes per-case; its argv log
//! doubles as the assertion surface for what ddcd actually asked the bus.

use std::path::PathBuf;
use std::time::Duration;

use axum::body::Body;
use axum::http::{Method, Request, StatusCode, header};
use http_body_util::BodyExt;
use tower::ServiceExt;

use ddcd::{Config, GUARD_HEADER, app};

struct Fake {
    dir: tempfile::TempDir,
}

impl Fake {
    /// Writes an executable fake m1ddc with the given body. `$LOG` expands to
    /// a per-fake log file path the script can append argv to.
    fn new(script_body: &str) -> Self {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempfile::tempdir().expect("tempdir");
        let log = dir.path().join("calls.log");
        let path = dir.path().join("m1ddc");
        let script = format!("#!/bin/bash\nLOG={}\n{}\n", log.display(), script_body);
        std::fs::write(&path, script).expect("write fake");
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).expect("chmod");
        Self { dir }
    }

    fn path(&self) -> PathBuf {
        self.dir.path().join("m1ddc")
    }

    fn calls(&self) -> Vec<String> {
        std::fs::read_to_string(self.dir.path().join("calls.log"))
            .unwrap_or_default()
            .lines()
            .map(str::to_string)
            .collect()
    }

    /// Generous per-call timeout: tests run in parallel and bash spawn under
    /// contention can take hundreds of ms. The timeout PATH is exercised by
    /// wedged_m1ddc_times_out_instead_of_hanging with its own short config.
    fn config(&self) -> Config {
        Config {
            m1ddc_path: self.path(),
            timeout: Duration::from_secs(3),
        }
    }
}

/// A well-behaved monitor: luminance 43, max 100, logs every call.
fn healthy_fake() -> Fake {
    Fake::new(
        r#"echo "$@" >> "$LOG"
case "$1 $2" in
  "get luminance") echo 43 ;;
  "max luminance") echo 100 ;;
  "set luminance") ;;
  *) echo "unknown command" ; exit 1 ;;
esac"#,
    )
}

fn request(method: Method, uri: &str, body: Option<serde_json::Value>) -> Request<Body> {
    let mut builder = Request::builder()
        .method(method)
        .uri(uri)
        .header(GUARD_HEADER, "1");
    let body = match body {
        Some(json) => {
            builder = builder.header(header::CONTENT_TYPE, "application/json");
            Body::from(json.to_string())
        }
        None => Body::empty(),
    };
    builder.body(body).unwrap()
}

async fn json_body(response: axum::response::Response) -> serde_json::Value {
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&bytes).unwrap()
}

#[tokio::test]
async fn requests_without_guard_header_are_refused() {
    let fake = healthy_fake();
    let response = app(fake.config())
        .oneshot(Request::get("/health").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn cors_preflight_is_refused() {
    let fake = healthy_fake();
    let response = app(fake.config())
        .oneshot(
            Request::builder()
                .method(Method::OPTIONS)
                .uri("/brightness")
                .header(header::ORIGIN, "https://evil.example")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::METHOD_NOT_ALLOWED);
}

#[tokio::test]
async fn browser_originating_requests_are_refused_even_with_header() {
    let fake = healthy_fake();
    let response = app(fake.config())
        .oneshot(
            Request::get("/health")
                .header(GUARD_HEADER, "1")
                .header(header::ORIGIN, "http://localhost:8377")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn health_reports_binary_presence() {
    let fake = healthy_fake();
    let response = app(fake.config())
        .oneshot(request(Method::GET, "/health", None))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = json_body(response).await;
    assert_eq!(body["status"], "ok");
    assert_eq!(body["m1ddc_present"], true);
}

#[tokio::test]
async fn get_brightness_reads_and_scales() {
    let fake = healthy_fake();
    let response = app(fake.config())
        .oneshot(request(Method::GET, "/brightness", None))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = json_body(response).await;
    assert_eq!(body["raw"], 43);
    assert_eq!(body["max"], 100);
    assert!((body["brightness"].as_f64().unwrap() - 0.43).abs() < 1e-9);
}

#[tokio::test]
async fn put_brightness_scales_against_max() {
    let fake = healthy_fake();
    let response = app(fake.config())
        .oneshot(request(
            Method::PUT,
            "/brightness",
            Some(serde_json::json!({ "brightness": 0.5 })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NO_CONTENT);
    assert_eq!(fake.calls(), vec!["max luminance", "set luminance 50"]);
}

#[tokio::test]
async fn put_brightness_rejects_out_of_range() {
    let fake = healthy_fake();
    for bad in [-0.1, 1.1, f64::NAN] {
        let response = app(fake.config())
            .oneshot(request(
                Method::PUT,
                "/brightness",
                Some(serde_json::json!({ "brightness": bad })),
            ))
            .await
            .unwrap();
        // NaN fails serde deserialization (400); the rest hit our range check (422).
        assert!(
            response.status() == StatusCode::UNPROCESSABLE_ENTITY
                || response.status() == StatusCode::BAD_REQUEST,
            "brightness {bad} accepted"
        );
        assert!(fake.calls().is_empty(), "bus touched for invalid input {bad}");
    }
}

#[tokio::test]
async fn insane_max_luminance_is_rejected_not_used() {
    // The Apr 2025 - Jun 2026 m1ddc HEAD bug: max read from the wrong byte
    // offset returns e.g. 25600 and every computed brightness is garbage.
    let fake = Fake::new(
        r#"echo "$@" >> "$LOG"
case "$1 $2" in
  "max luminance") echo 25600 ;;
  *) echo 43 ;;
esac"#,
    );
    let response = app(fake.config())
        .oneshot(request(Method::GET, "/brightness", None))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_GATEWAY);
}

#[tokio::test]
async fn wedged_m1ddc_times_out_instead_of_hanging() {
    let fake = Fake::new(r#"sleep 30"#);
    let config = Config {
        m1ddc_path: fake.path(),
        timeout: Duration::from_millis(500),
    };
    let started = std::time::Instant::now();
    let response = app(config)
        .oneshot(request(Method::GET, "/brightness", None))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::GATEWAY_TIMEOUT);
    assert!(
        started.elapsed() < Duration::from_secs(5),
        "timeout did not bound the call"
    );
}

#[tokio::test]
async fn m1ddc_failure_surfaces_as_bad_gateway() {
    let fake = Fake::new(r#"echo "DDC communication failure"; exit 1"#);
    let response = app(fake.config())
        .oneshot(request(Method::GET, "/brightness", None))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_GATEWAY);
    let body = json_body(response).await;
    assert!(
        body["error"].as_str().unwrap().contains("DDC communication failure"),
        "m1ddc's stdout error text should surface: {body}"
    );
}

#[tokio::test]
async fn concurrent_requests_never_interleave_on_the_bus() {
    // DDC/I2C is single-master: the mutex must serialize transactions. The
    // fake records begin/end markers; interleaving shows as nested begins.
    let fake = Fake::new(
        r#"echo "begin" >> "$LOG"
sleep 0.1
echo "end" >> "$LOG"
case "$1 $2" in
  "get luminance") echo 43 ;;
  "max luminance") echo 100 ;;
esac"#,
    );
    let shared_app = app(fake.config());
    let (r1, r2) = tokio::join!(
        shared_app.clone().oneshot(request(Method::GET, "/brightness", None)),
        shared_app.clone().oneshot(request(Method::GET, "/brightness", None)),
    );
    assert_eq!(r1.unwrap().status(), StatusCode::OK);
    assert_eq!(r2.unwrap().status(), StatusCode::OK);

    let calls = fake.calls();
    assert_eq!(calls.iter().filter(|l| *l == "begin").count(), 4, "{calls:?}");
    let mut depth = 0i32;
    for line in &calls {
        match line.as_str() {
            "begin" => {
                depth += 1;
                assert_eq!(depth, 1, "interleaved DDC transactions: {calls:?}");
            }
            "end" => depth -= 1,
            _ => {}
        }
    }
}
