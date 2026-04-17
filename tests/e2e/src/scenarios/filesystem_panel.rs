use std::time::Duration;

use crate::actor::Actor;
use crate::locators::filesystem;

pub async fn run(actor: &Actor) -> crate::actor::Result {
    // Panel is visible with heading and both storage sections
    actor.expect(filesystem::root()).to_be_visible().await?;
    actor.expect(filesystem::heading()).to_be_visible().await?;
    actor.expect(filesystem::sd_section()).to_be_visible().await?;
    actor.expect(filesystem::littlefs_section()).to_be_visible().await?;

    // "Add file..." label is visible (SD upload trigger)
    actor.expect(filesystem::add_file_label()).to_be_visible().await?;

    // Wait for files to load (skeleton should disappear)
    actor
        .expect(filesystem::file_row("data.csv"))
        .with_timeout(Duration::from_secs(15))
        .to_be_visible()
        .await?;

    // CSV file is clickable for preview
    actor.locate(filesystem::file_row("data.csv")).await.click(None).await?;
    actor
        .expect(filesystem::csv_preview_dialog())
        .with_timeout(Duration::from_secs(5))
        .to_be_visible()
        .await?;

    // Preview dialog has a close button
    actor.expect(filesystem::preview_close()).to_be_visible().await?;
    actor.locate(filesystem::preview_close()).await.click(None).await?;
    actor.expect(filesystem::csv_preview_dialog()).not().to_be_visible().await?;

    Ok(())
}
