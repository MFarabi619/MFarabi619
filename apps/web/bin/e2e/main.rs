#![allow(dead_code)]

mod actor;
mod locators;
mod scenarios;
mod tasks;

use actor::Actor;
use playwright_rs::{BrowserContextOptions, LaunchOptions, Playwright};
use tasks::Navigate;

macro_rules! scenario {
    ($actor:expr, $name:expr, $run:path, $p:expr, $f:expr) => {{
        match $run(&$actor).await {
            Ok(()) => {
                $p += 1;
                println!("  ✓ {}", $name);
            }
            Err(e) => {
                $f += 1;
                eprintln!("  ✗ {}: {e}", $name);
            }
        }
    }};
}

#[tokio::main]
async fn main() {
    let playwright = Playwright::launch().await.expect("launch playwright");
    let browser = playwright
        .chromium()
        .launch_with_options(LaunchOptions::default().headless(false))
        .await
        .expect("launch browser");

    let context = browser
        .new_context_with_options(
            BrowserContextOptions::builder()
                .permissions(vec![
                    "clipboard-read".into(),
                    "clipboard-write".into(),
                    "notifications".into(),
                ])
                .build(),
        )
        .await
        .expect("create context");
    let page = context.new_page().await.expect("new page");
    let actor = Actor::new(page);
    actor.attempts_to(Navigate::to("/")).await.expect("navigate to app");

    let mut passed = 0u32;
    let mut failed = 0u32;

    scenario!(actor, "navigation", scenarios::navigation::run, passed, failed);
    scenario!(actor, "layout", scenarios::layout::run, passed, failed);
    scenario!(actor, "connected home", scenarios::connected_home::run, passed, failed);
    scenario!(actor, "status badge", scenarios::status_badge::run, passed, failed);
    scenario!(actor, "network sheet", scenarios::network_sheet::run, passed, failed);
    scenario!(actor, "command palette", scenarios::command_palette::run, passed, failed);
    scenario!(actor, "sleep panel", scenarios::sleep_panel::run, passed, failed);
    scenario!(actor, "filesystem panel", scenarios::filesystem_panel::run, passed, failed);
    scenario!(actor, "measurement panel", scenarios::measurement_panel::run, passed, failed);
    scenario!(actor, "flash panel", scenarios::flash_panel::run, passed, failed);
    scenario!(actor, "not found", scenarios::not_found::run, passed, failed);

    context.close().await.ok();
    browser.close().await.ok();

    println!("\n{passed} passed, {failed} failed");
    if failed > 0 {
        std::process::exit(1);
    }
}
