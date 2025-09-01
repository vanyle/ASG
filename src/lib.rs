pub mod asg;

use std::{
    path::{Path, PathBuf},
    time::Duration,
};

use axum::{
    Router,
    extract::{
        WebSocketUpgrade,
        ws::{Message, WebSocket},
    },
    response::Response,
    routing::{self},
};

use asg::process_files;
use asg::{lua_environment::LuaEnvironment, process_file};
use notify_debouncer_full::{
    DebounceEventResult, DebouncedEvent, new_debouncer, notify::RecursiveMode,
};
use tokio::sync::broadcast::{self, Sender};
use tower_http::services::{ServeDir, ServeFile};

pub async fn lib_main(input_directory: &Path, output_directory: &Path) {
    let mut env = compile_without_server(input_directory, output_directory, None);

    let (debounce_event_sender, mut debounce_receiver) = broadcast::channel(16);
    let cloned_sender = debounce_event_sender.clone();
    let is_live_reload_enabled = env.is_enabled("livereload");
    // The debouncer needs to stay alive for the whole program.
    let mut debouncer = new_debouncer(
        Duration::from_millis(100),
        None,
        move |result: DebounceEventResult| match result {
            Ok(events) => events.iter().for_each(|event| {
                let _ = debounce_event_sender.send(event.clone());
            }),
            Err(errors) => errors.iter().for_each(|error| println!("{error:?}")),
        },
    )
    .unwrap();

    if is_live_reload_enabled {
        println!("👀 Watching {}", input_directory.to_string_lossy());
        let watch_result = debouncer.watch(input_directory, RecursiveMode::Recursive);
        if let Err(e) = watch_result {
            println!("Error: Could not watch because {e}");
        }
    }

    let port: Option<String> = env.get_config("port");

    if let Some(port) = port {
        let file_404 = output_directory
            .join("404.html")
            .to_string_lossy()
            .to_string();

        let serve_dir = ServeDir::new(output_directory).fallback(ServeFile::new(file_404));

        tokio::spawn(async move {
            let app = Router::new()
                .route(
                    "/ws",
                    routing::any(async move |ws: WebSocketUpgrade| {
                        websocket_route(ws, cloned_sender)
                    }),
                )
                .fallback_service(serve_dir.clone());

            let listening_addr = format!("0.0.0.0:{port}");
            let printed_addr = format!("localhost:{port}");
            println!("👂 Listening on {listening_addr}\n>>> http://{printed_addr}\n");

            let maybe_listener = tokio::net::TcpListener::bind(listening_addr).await;

            let listener = maybe_listener.unwrap_or_else(|_| {
                eprintln!("Error: Could not bind to port {port}. Is it already in use?");
                std::process::exit(1);
            });
            axum::serve(listener, app).await.unwrap();
        });
    }

    // Perform the file processing on the main thread.
    if is_live_reload_enabled {
        loop {
            let event = debounce_receiver.recv().await;
            let Ok(event) = event else {
                break;
            };
            for path in &event.paths {
                if env.is_enabled("debugInfo") {
                    println!("Processing {}", path.display());
                }
                process_file(
                    &mut env,
                    event.kind,
                    path,
                    input_directory,
                    output_directory,
                );
            }
        }
    }
}

fn websocket_route(
    ws: WebSocketUpgrade,
    debounce_event_receiver: Sender<DebouncedEvent>,
) -> Response {
    ws.on_upgrade(async |socket| handle_websocket(socket, debounce_event_receiver).await)
}

async fn handle_websocket(mut socket: WebSocket, debounce_event_receiver: Sender<DebouncedEvent>) {
    let mut receiver = debounce_event_receiver.subscribe();
    loop {
        let event = receiver.recv().await;
        if event.is_err() {
            break;
        }
        let result = socket.send(Message::text("reload")).await;
        if result.is_err() {
            break;
        }
    }
}

pub fn compile_without_server(
    input_directory: &Path,
    output_directory: &Path,
    asset_directory: Option<PathBuf>,
) -> LuaEnvironment {
    if !input_directory.exists() {
        println!(
            "Input does not exist: {}",
            input_directory.to_string_lossy()
        );
        std::process::exit(1);
    }

    if !output_directory.exists() {
        let _ = std::fs::create_dir_all(output_directory);
    }

    let mut env = LuaEnvironment::new(input_directory, output_directory, asset_directory);
    process_files(&mut env, input_directory, output_directory);
    env
}
