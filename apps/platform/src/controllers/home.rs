use loco_rs::prelude::*;

async fn hello(State(_ctx): State<AppContext>) -> Result<Response> {
  format::text("ola, mundo")
}

pub fn routes() -> Routes {
  Routes::new().prefix("home").add("/hello", get(hello))
}
