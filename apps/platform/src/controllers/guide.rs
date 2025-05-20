#![allow(clippy::missing_errors_doc)]
#![allow(clippy::unnecessary_struct_initialization)]
#![allow(clippy::unused_async)]
use loco_rs::prelude::*;
use axum::debug_handler;

#[debug_handler]
pub async fn index(State(_ctx): State<AppContext>) -> Result<Response> {
    format::text("hello")
}

pub fn routes() -> Routes {
    Routes::new()
        .prefix("api/guides/")
        .add("/", get(index))
}
