use playwright_rs::{LaunchOptions, Playwright};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("Starting Playwright...");

    let playwright = Playwright::launch().await?;

    println!("Launching browser (headless: false)...");
    let options = LaunchOptions::default().headless(true);

    let browser = playwright.chromium().launch_with_options(options).await?;
    let context = browser.new_context().await?;
    let page = context.new_page().await?;

    println!("Navigating to example.com...");

    let response = page
        .goto("https://microvisor.systems", None)
        .await?
        .expect("https://microvisor.systems should return a response");

    assert!(response.ok());
    assert_eq!(response.status(), 200);

    let title = page.title().await?;
    let url = page.url();
    println!("Title: {}", title);
    println!("URL: {}", url);

    // println!("Pausing execution. Look for the Playwright Inspector window!");
    // println!("Press 'Resume' in the Inspector to close the browser and exit.");
    // page.pause().await?;

    // println!("Resumed! Closing browser...");
    browser.close().await?;

    Ok(())
}
