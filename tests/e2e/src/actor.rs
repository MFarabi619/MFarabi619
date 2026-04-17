use playwright_rs::{expect, expect_page, Page};
use std::time::Duration;

use crate::locators::Locator;

pub type Result = std::result::Result<(), Box<dyn std::error::Error>>;

pub trait Task {
    async fn perform(self, page: &Page) -> Result;
}

pub struct Actor {
    page: Page,
}

impl Actor {
    pub fn new(page: Page) -> Self {
        Self { page }
    }

    pub async fn attempts_to(&self, task: impl Task) -> Result {
        task.perform(&self.page).await
    }

    pub fn expect(&self, locator: Locator) -> PendingExpectation<'_> {
        PendingExpectation {
            page: &self.page,
            locator,
            negate: false,
            timeout: None,
        }
    }

    pub fn expect_page(&self) -> playwright_rs::PageExpectation {
        expect_page(&self.page)
    }

    pub async fn locate(&self, locator: Locator) -> playwright_rs::Locator {
        locator.resolve(&self.page).await
    }

    pub fn page(&self) -> &Page {
        &self.page
    }
}

pub struct PendingExpectation<'a> {
    page: &'a Page,
    locator: Locator,
    negate: bool,
    timeout: Option<Duration>,
}

macro_rules! expect_method {
    ($name:ident) => {
        pub async fn $name(self) -> Result {
            let (el, negate, timeout) = self.resolve().await;
            let mut e = expect(el);
            if negate { e = e.not(); }
            if let Some(t) = timeout { e = e.with_timeout(t); }
            e.$name().await?;
            Ok(())
        }
    };
    ($name:ident, $arg:ident: $ty:ty) => {
        pub async fn $name(self, $arg: $ty) -> Result {
            let (el, negate, timeout) = self.resolve().await;
            let mut e = expect(el);
            if negate { e = e.not(); }
            if let Some(t) = timeout { e = e.with_timeout(t); }
            e.$name($arg).await?;
            Ok(())
        }
    };
}

impl PendingExpectation<'_> {
    pub fn not(mut self) -> Self {
        self.negate = true;
        self
    }

    pub fn with_timeout(mut self, timeout: Duration) -> Self {
        self.timeout = Some(timeout);
        self
    }

    async fn resolve(self) -> (playwright_rs::Locator, bool, Option<Duration>) {
        let el = self.locator.resolve(self.page).await;
        (el, self.negate, self.timeout)
    }

    expect_method!(to_be_visible);
    expect_method!(to_be_hidden);
    expect_method!(to_be_enabled);
    expect_method!(to_be_disabled);
    expect_method!(to_be_checked);
    expect_method!(to_be_unchecked);
    expect_method!(to_be_editable);
    expect_method!(to_be_focused);
    expect_method!(to_have_text, expected: &str);
    expect_method!(to_have_text_regex, pattern: &str);
    expect_method!(to_contain_text, expected: &str);
    expect_method!(to_contain_text_regex, pattern: &str);
    expect_method!(to_have_value, expected: &str);
    expect_method!(to_have_value_regex, pattern: &str);

    pub async fn to_have_screenshot(
        self,
        baseline_path: impl AsRef<std::path::Path>,
        options: Option<playwright_rs::ScreenshotAssertionOptions>,
    ) -> Result {
        let (el, negate, timeout) = self.resolve().await;
        let mut e = expect(el);
        if negate { e = e.not(); }
        if let Some(t) = timeout { e = e.with_timeout(t); }
        e.to_have_screenshot(baseline_path, options).await?;
        Ok(())
    }
}
