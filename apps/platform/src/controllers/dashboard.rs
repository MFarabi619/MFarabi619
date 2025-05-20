use loco_rs::prelude::*;

use reate::views;

pub async fn render_home(ViewEngine(v): ViewEngine<TeraView>) -> Result<impl IntoResponse>{
  views::dashboard::home(v)
}

pub fn routes() -> Routes {
  Routes::new().add("/", get(render_home))
}
