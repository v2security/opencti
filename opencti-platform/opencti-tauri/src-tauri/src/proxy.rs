use axum::{
    body::Body,
    extract::{Request, ws::{WebSocketUpgrade, WebSocket, Message as AxumMessage}},
    http::{Method, StatusCode},
    response::Response,
    routing::{any, get},
    Router,
};
use futures_util::{SinkExt, StreamExt};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::sync::RwLock;
use tokio_tungstenite::tungstenite::Message;
use tower_http::cors::CorsLayer;

const BACKEND_URL: &str = "http://163.223.58.7:8080";
const API_TOKEN: &str = "ff91eda6-7317-4de3-96a3-5f8b7cc4a01f";
const LOGIN_EMAIL: &str = "admin@v2secure.vn";
const LOGIN_PASSWORD: &str = "T0ikonho@123"; // TODO: Move to secure storage or config file

// Shared state for session cookies
type SessionCookies = Arc<RwLock<Option<String>>>;

pub async fn start_proxy_server() {
    println!("🔐 Initializing proxy with session authentication...");
    
    // Create shared session state
    let session_cookies: SessionCookies = Arc::new(RwLock::new(None));
    
    // Establish initial session
    if let Err(e) = establish_session(session_cookies.clone()).await {
        eprintln!("❌ Failed to establish session: {}", e);
        eprintln!("⚠️  Proxy will start but authentication may fail");
    }
    
    let cors = CorsLayer::permissive();

    let app = Router::new()
        .route("/graphql", get({
            let cookies = session_cookies.clone();
            move |ws: WebSocketUpgrade, req: Request| websocket_handler(ws, req, cookies)
        }).post({
            let cookies = session_cookies.clone();
            move |req: Request| graphql_http_handler(req, cookies)
        }))
        .fallback(any({
            let cookies = session_cookies.clone();
            move |method: Method, req: Request| http_proxy_handler(method, req, cookies)
        }))
        .layer(cors);

    let addr = SocketAddr::from(([127, 0, 0, 1], 7777));
    println!("🚀 Proxy server listening on http://{}", addr);
    println!("📡 Forwarding to: {}", BACKEND_URL);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("Failed to bind proxy server");

    axum::serve(listener, app)
        .await
        .expect("Failed to start proxy server");
}

// Establish session by performing login with email/password
async fn establish_session(cookies: SessionCookies) -> Result<(), Box<dyn std::error::Error>> {
    println!("🔑 Establishing session with backend...");
    println!("📧 Login email: {}", LOGIN_EMAIL);
    
    let client = reqwest::Client::builder()
        .cookie_store(true)
        .danger_accept_invalid_certs(true)
        .build()?;
    
    // Perform GraphQL login mutation to get session cookies
    let login_query = serde_json::json!({
        "query": "mutation($input: UserLoginInput!) { token(input: $input) }",
        "variables": {
            "input": {
                "email": LOGIN_EMAIL,
                "password": LOGIN_PASSWORD
            }
        }
    });
    
    let response = client
        .post(format!("{}/graphql", BACKEND_URL))
        .header("Content-Type", "application/json")
        .json(&login_query)
        .send()
        .await?;
    
    let status = response.status();
    println!("🔐 Login response status: {}", status);
    
    // Extract session cookies from response
    let mut cookie_strings = Vec::new();
    for cookie in response.cookies() {
        let cookie_str = format!("{}={}", cookie.name(), cookie.value());
        cookie_strings.push(cookie_str);
        println!("🍪 Cookie: {}", cookie.name());
    }
    
    // Log response body for debugging
    let body = response.text().await?;
    if body.contains("error") || body.contains("Error") {
        println!("⚠️  Login response: {}", body);
    }
    
    if !cookie_strings.is_empty() {
        let cookies_combined = cookie_strings.join("; ");
        let mut cookies_write = cookies.write().await;
        *cookies_write = Some(cookies_combined);
        println!("✅ Session established successfully with login");
        println!("🍪 Total cookies stored: {}", cookie_strings.len());
        return Ok(());
    }
    
    println!("⚠️  No session cookies received from login");
    println!("⚠️  Falling back to Bearer token authentication");
    Ok(())
}

// WebSocket upgrade handler
async fn websocket_handler(
    ws: WebSocketUpgrade,
    req: Request,
    session_cookies: SessionCookies,
) -> Response {
    let uri = req.uri();
    let path = uri.path();
    let query = uri.query().unwrap_or("");
    
    let target_ws_url = if query.is_empty() {
        format!("ws://163.223.58.7:8080{}", path)
    } else {
        format!("ws://163.223.58.7:8080{}?{}", path, query)
    };
    
    println!("🔌 WebSocket upgrade request to {}", target_ws_url);
    
    ws.on_upgrade(move |socket| async move {
        handle_websocket(socket, target_ws_url, session_cookies).await
    })
}

// HTTP handler for GraphQL POST requests
async fn graphql_http_handler(
    req: Request,
    session_cookies: SessionCookies,
) -> Result<Response, StatusCode> {
    http_proxy_handler(Method::POST, req, session_cookies).await
}

// HTTP proxy handler
async fn http_proxy_handler(
    method: Method,
    req: Request,
    session_cookies: SessionCookies,
) -> Result<Response, StatusCode> {
    let uri = req.uri();
    let path = uri.path();
    let query = uri.query().unwrap_or("");

    let target_url = if query.is_empty() {
        format!("{}{}", BACKEND_URL, path)
    } else {
        format!("{}{}?{}", BACKEND_URL, path, query)
    };

    println!("📤 {} {}", method, target_url);

    let headers = req.headers().clone();
    let body_bytes = axum::body::to_bytes(req.into_body(), usize::MAX)
        .await
        .map_err(|_| StatusCode::BAD_REQUEST)?;

    let client = reqwest::Client::builder()
        .cookie_store(true)
        .danger_accept_invalid_certs(true)
        .build()
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let mut backend_req = client
        .request(method.clone(), &target_url)
        .header("Authorization", format!("Bearer {}", API_TOKEN))
        .body(body_bytes.to_vec());

    // Add session cookies if available
    let cookies_read = session_cookies.read().await;
    if let Some(cookie_str) = cookies_read.as_ref() {
        backend_req = backend_req.header("Cookie", cookie_str);
    }

    // Copy other headers (except Host, Authorization, Cookie - we set our own)
    for (key, value) in headers.iter() {
        let key_lower = key.as_str().to_lowercase();
        if key_lower != "host" && key_lower != "authorization" && key_lower != "cookie" {
            if let Ok(value_str) = value.to_str() {
                backend_req = backend_req.header(key.as_str(), value_str);
            }
        }
    }

    let response = backend_req
        .send()
        .await
        .map_err(|e| {
            eprintln!("❌ Proxy error: {}", e);
            StatusCode::BAD_GATEWAY
        })?;

    println!("📥 Response: {}", response.status());

    let status = response.status();
    let headers = response.headers().clone();
    let body_bytes = response
        .bytes()
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let mut resp_builder = Response::builder().status(status);

    // Copy response headers
    for (key, value) in headers.iter() {
        resp_builder = resp_builder.header(key, value);
    }

    resp_builder
        .body(Body::from(body_bytes))
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

async fn handle_websocket(
    client_ws: WebSocket,
    target_url: String,
    session_cookies: SessionCookies,
) {
    println!("🔗 Establishing WebSocket connection to backend...");
    
    let ws_url = match target_url.parse::<tokio_tungstenite::tungstenite::http::Uri>() {
        Ok(uri) => uri,
        Err(e) => {
            eprintln!("❌ Failed to parse WebSocket URL: {}", e);
            return;
        }
    };
    
    // Build WebSocket request with session cookies
    let mut request_builder = tokio_tungstenite::tungstenite::http::Request::builder()
        .uri(ws_url)
        .header("Host", "163.223.58.7:8080")
        .header("Connection", "Upgrade")
        .header("Upgrade", "websocket")
        .header("Sec-WebSocket-Version", "13")
        .header("Sec-WebSocket-Key", tokio_tungstenite::tungstenite::handshake::client::generate_key())
        .header("Sec-WebSocket-Protocol", "graphql-transport-ws");
    
    // Add session cookies if available
    let cookies_read = session_cookies.read().await;
    if let Some(cookie_str) = cookies_read.as_ref() {
        request_builder = request_builder.header("Cookie", cookie_str);
        println!("🔐 Using session cookie for WebSocket authentication");
    } else {
        // Fallback to Bearer token
        request_builder = request_builder.header("Authorization", format!("Bearer {}", API_TOKEN));
        println!("🔐 Using Bearer token for WebSocket authentication");
    }
    drop(cookies_read);
    
    let request = request_builder.body(()).expect("Failed to build request");
    
    let backend_ws = match tokio_tungstenite::connect_async(request).await {
        Ok((ws, response)) => {
            println!("✅ WebSocket connected to backend");
            println!("📋 Response status: {} {}", response.status().as_u16(), response.status().canonical_reason().unwrap_or(""));
            ws
        },
        Err(e) => {
            eprintln!("❌ Failed to connect to backend WebSocket: {}", e);
            return;
        }
    };
    
    let (mut backend_tx, mut backend_rx) = backend_ws.split();
    let (mut client_tx, mut client_rx) = client_ws.split();
    
    // Forward messages from client to backend
    let client_to_backend = async move {
        while let Some(msg) = client_rx.next().await {
            let msg = match msg {
                Ok(m) => m,
                Err(e) => {
                    eprintln!("❌ Error receiving from client: {}", e);
                    break;
                }
            };
            
            match &msg {
                AxumMessage::Text(text) => println!("📨 Client → Backend: {}", text),
                AxumMessage::Binary(data) => println!("📨 Client → Backend: {} bytes", data.len()),
                AxumMessage::Close(frame) => {
                    println!("🔌 Client close: {:?}", frame);
                    let _ = backend_tx.send(Message::Close(None)).await;
                    break;
                }
                _ => {}
            }
            
            let backend_msg = match msg {
                AxumMessage::Text(text) => Message::Text(text.to_string()),
                AxumMessage::Binary(data) => Message::Binary(data.to_vec()),
                AxumMessage::Ping(data) => Message::Ping(data.to_vec()),
                AxumMessage::Pong(data) => Message::Pong(data.to_vec()),
                AxumMessage::Close(_) => break,
            };
            
            if let Err(e) = backend_tx.send(backend_msg).await {
                eprintln!("❌ Error forwarding to backend: {}", e);
                break;
            }
        }
    };
    
    // Forward messages from backend to client
    let backend_to_client = async move {
        while let Some(msg) = backend_rx.next().await {
            let msg = match msg {
                Ok(m) => m,
                Err(e) => {
                    eprintln!("❌ Error receiving from backend: {}", e);
                    break;
                }
            };
            
            match &msg {
                Message::Text(text) => println!("📨 Backend → Client: {}", text),
                Message::Binary(data) => println!("📨 Backend → Client: {} bytes", data.len()),
                Message::Close(frame) => {
                    println!("🔌 Backend close: {:?}", frame);
                    let _ = client_tx.send(AxumMessage::Close(None)).await;
                    break;
                }
                Message::Frame(_) => {}
                _ => {}
            }
            
            let client_msg = match msg {
                Message::Text(text) => AxumMessage::Text(text.into()),
                Message::Binary(data) => AxumMessage::Binary(data.into()),
                Message::Ping(data) => AxumMessage::Ping(data.into()),
                Message::Pong(data) => AxumMessage::Pong(data.into()),
                Message::Close(_) => break,
                Message::Frame(_) => continue,
            };
            
            if let Err(e) = client_tx.send(client_msg).await {
                eprintln!("❌ Error forwarding to client: {}", e);
                break;
            }
        }
    };
    
    // Run both forwarding tasks concurrently
    tokio::select! {
        _ = client_to_backend => println!("🔌 Client to backend connection closed"),
        _ = backend_to_client => println!("🔌 Backend to client connection closed"),
    }
    
    println!("🔌 WebSocket proxy connection fully closed");
}
