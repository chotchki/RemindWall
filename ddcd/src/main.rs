use std::net::{Ipv4Addr, SocketAddr};

use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "ddcd=info".into()))
        .init();

    let config = ddcd::Config::from_env();
    let port: u16 = std::env::var("DDCD_PORT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(8377);

    // Loopback ONLY - this box serves public traffic; ddcd must never be
    // reachable from off-machine.
    let addr = SocketAddr::from((Ipv4Addr::LOCALHOST, port));

    tracing::info!(
        %addr,
        m1ddc = %config.m1ddc_path.display(),
        timeout_ms = config.timeout.as_millis(),
        "ddcd starting"
    );

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .unwrap_or_else(|e| panic!("cannot bind {addr}: {e}"));

    axum::serve(listener, ddcd::app(config))
        .await
        .expect("server crashed");
}
