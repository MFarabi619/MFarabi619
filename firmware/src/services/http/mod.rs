use alloc::string::String as AllocString;

use defmt::info;
use embassy_executor::Spawner;
use embassy_net::Stack;
use embassy_time::Duration;
use picoserve::AppBuilder;
use picoserve::routing::{get, get_service, parse_path_segment};
use static_cell::StaticCell;

pub use crate::config::http::PORT as HTTP_SERVER_PORT;

mod api;
mod files;
mod upload;

macro_rules! mk_static {
    ($type:ty, $value:expr) => {{
        static STATIC_CELL: StaticCell<$type> = StaticCell::new();
        STATIC_CELL.uninit().write($value)
    }};
}

pub struct HttpAppProps {
    pub stack: Stack<'static>,
}

impl picoserve::AppBuilder for HttpAppProps {
    type PathRouter = impl picoserve::routing::PathRouter;

    fn build_app(self) -> picoserve::Router<Self::PathRouter> {
        picoserve::Router::new()
            .route("/", get_service(files::IndexService))
            .route(
                parse_path_segment::<AllocString>(),
                get_service(files::StaticFileService).post_service(upload::FileUploadService),
            )
            .route("/api", get(api::api_handler))
    }
}

pub static CONFIG: picoserve::Config = picoserve::Config::new(picoserve::Timeouts {
    start_read_request: Duration::from_secs(5),
    persistent_start_read_request: Duration::from_secs(5),
    read_request: Duration::from_secs(2),
    write: Duration::from_secs(30),
})
.keep_connection_alive();

pub fn spawn(spawner: &Spawner, stack: Stack<'static>) {
    const WEB_TASK_POOL_SIZE: usize = 1;

    let app = mk_static!(
        picoserve::AppRouter<HttpAppProps>,
        HttpAppProps { stack }.build_app()
    );

    for task_id in 0..WEB_TASK_POOL_SIZE {
        spawner.spawn(task(task_id, stack, app).unwrap());
    }

    info!("HTTP server listening on port {}", HTTP_SERVER_PORT);
}

#[embassy_executor::task]
pub async fn task(
    task_id: usize,
    stack: Stack<'static>,
    app: &'static picoserve::AppRouter<HttpAppProps>,
) -> ! {
    let mut tcp_rx_buffer = alloc::vec![0u8; 2048];
    let mut tcp_tx_buffer = alloc::vec![0u8; 2048];
    let mut http_buffer = alloc::vec![0u8; 4096];

    picoserve::Server::new(app, &CONFIG, &mut http_buffer)
        .listen_and_serve(
            task_id,
            stack,
            HTTP_SERVER_PORT,
            &mut tcp_rx_buffer,
            &mut tcp_tx_buffer,
        )
        .await
        .into_never()
}
