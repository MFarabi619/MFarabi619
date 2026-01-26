use playwright_rs::{LaunchOptions, Playwright, expect};
use std::time::Duration;

#[derive(Clone, Debug)]
struct WebsiteEntry {
    website_name: &'static str,
    website_url: &'static str,
}

async fn test_website(
    browser_page: &playwright_rs::Page,
    website: &WebsiteEntry,
) -> Result<(), Box<dyn std::error::Error>> {
    println!("\n==============================");
    println!("Testing: {}", website.website_name);
    println!("URL:     {}", website.website_url);

    let navigation_response = browser_page
        .goto(website.website_url, None)
        .await?
        .expect("Expected navigation response");

    assert!(navigation_response.ok());
    assert_eq!(navigation_response.status(), 200);

    println!("✓ HTTP 200");

    if website.website_name == "Microvisor" {
        let header_locator = browser_page.locator("header").await;
        expect(header_locator.clone()).to_be_visible().await?;
        println!("✓ Header visible");

        let first_heading_locator = browser_page.locator("h1").await.first();
        expect(first_heading_locator.clone())
            .not()
            .to_be_visible()
            .await?;
        println!("✓ First h1 hidden");
    }

    if website.website_name == "Grafana" {
        let page_title = browser_page.title().await?;
        assert!(page_title.contains("Grafana"));
        println!("✓ Title contains Grafana");
    }

    // ----------------------------------------

    let final_title = browser_page.title().await?;
    let final_url = browser_page.url();

    println!("Final title: {}", final_title);
    println!("Final URL:   {}", final_url);

    Ok(())
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let websites: &[WebsiteEntry] = &[
        WebsiteEntry {
            website_name: "Microvisor Systems Landing Page",
            website_url: "https://microvisor.systems",
        },
        WebsiteEntry {
            website_name: "OpenWS Dashboard",
            website_url: "https://openws.org",
        },
        // WebsiteEntry {
        //     website_name: "Grafana",
        //     website_url: "https://grafana.openws.org",
        // },
        WebsiteEntry {
            website_name: "OpenWS AI",
            website_url: "https://ai.openws.org",
        },
        WebsiteEntry {
            website_name: "OpenWS Docs",
            website_url: "https://docs.openws.org",
        },
        WebsiteEntry {
            website_name: "OpenWS Admin",
            website_url: "https://admin.openws.org",
        },
        WebsiteEntry {
            website_name: "OpenWS NixOS Demo",
            website_url: "https://demo.openws.org",
        },
        WebsiteEntry {
            website_name: "OpenWS Raspberry Pi Trixie Demo",
            website_url: "https://rpi5.openws.org",
        },
    ];

    println!("Starting Playwright...");
    let playwright = Playwright::launch().await?;

    let launch_options = LaunchOptions::default().headless(true);

    let browser = playwright
        .chromium()
        .launch_with_options(launch_options)
        .await?;

    let context = browser.new_context().await?;

    let mut failed_websites: Vec<(&'static str, String)> = Vec::new();

    for website in websites {
        let page = context.new_page().await?;

        let result =
            tokio::time::timeout(Duration::from_secs(60), test_website(&page, website)).await;

        match result {
            Ok(Ok(())) => {
                println!("✅ PASS: {}", website.website_name);
            }

            Ok(Err(error)) => {
                println!("❌ FAIL: {}", website.website_name);
                failed_websites.push((website.website_name, error.to_string()));
            }

            Err(_) => {
                println!("❌ FAIL: {} (timeout)", website.website_name);
                failed_websites.push((website.website_name, "timeout".into()));
            }
        }

        page.close().await.ok();
    }

    browser.close().await?;

    if !failed_websites.is_empty() {
        eprintln!("\n==============================");
        eprintln!("Failures:");

        for (name, reason) in failed_websites {
            eprintln!("- {}: {}", name, reason);
        }

        std::process::exit(1);
    }

    println!("\nAll websites passed 🎉");

    Ok(())
}
