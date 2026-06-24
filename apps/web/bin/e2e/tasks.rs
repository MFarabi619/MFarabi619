use crate::actor::{Result, Task};
use playwright_rs::Page;

pub fn base_url() -> String {
    std::env::var("WEB_BASE_URL").unwrap_or_else(|_| "http://localhost:8080".to_string())
}

pub struct Navigate;

impl Navigate {
    pub fn to(path: &'static str) -> NavigateTo {
        NavigateTo { path }
    }
}

pub(crate) struct NavigateTo {
    path: &'static str,
}

impl Task for NavigateTo {
    async fn perform(self, page: &Page) -> Result {
        let url = if self.path.starts_with("http") {
            self.path.to_string()
        } else {
            format!("{}{}", base_url(), self.path)
        };
        page.goto(&url, None).await?;
        Ok(())
    }
}
