use crate::actor::Actor;
use crate::locators::{command_palette, flash};

pub async fn run(actor: &Actor) -> crate::actor::Result {
    actor.page().keyboard().press("Control+k", None).await?;
    actor.expect(command_palette::root()).to_be_visible().await?;
    actor.expect(command_palette::search_input()).to_be_visible().await?;

    actor.expect(command_palette::command("Sample Sensors")).to_be_visible().await?;
    actor.expect(command_palette::command("Open API")).to_be_visible().await?;
    actor.expect(command_palette::command("Upload File to SD")).to_be_visible().await?;
    actor.expect(command_palette::command("Scan Networks")).to_be_visible().await?;
    actor.expect(command_palette::command("Firmware Flash")).to_be_visible().await?;

    // Type to filter
    actor.expect(command_palette::command("Sample Sensors")).to_be_visible().await?;
    actor.expect(command_palette::command("Open API")).to_be_hidden().await?;

    // Clear and verify all come back
    actor.locate(command_palette::search_input()).await.fill("", None).await?;
    actor.expect(command_palette::command("Open API")).to_be_visible().await?;

    // Action navigates to the flash section and closes the palette
    actor.locate(command_palette::command("Firmware Flash")).await.click(None).await?;
    actor.expect(command_palette::root()).to_be_hidden().await?;
    actor.expect(flash::root()).to_be_visible().await?;

    // Reopen and Escape closes
    actor.page().keyboard().press("Control+k", None).await?;
    actor.page().keyboard().press("Escape", None).await?;
    actor.expect(command_palette::root()).to_be_hidden().await?;

    Ok(())
}
