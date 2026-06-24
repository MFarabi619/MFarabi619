use crate::actor::Actor;
use crate::locators::sleep;

pub async fn run(actor: &Actor) -> crate::actor::Result {
    // Panel is visible with heading
    actor.expect(sleep::root()).to_be_visible().await?;
    actor.expect(sleep::heading()).to_be_visible().await?;

    // Preset buttons are visible
    actor.expect(sleep::preset_button("1m")).to_be_visible().await?;
    actor.expect(sleep::preset_button("5m")).to_be_visible().await?;
    actor.expect(sleep::preset_button("15m")).to_be_visible().await?;
    actor.expect(sleep::preset_button("1h")).to_be_visible().await?;
    actor.expect(sleep::custom_button()).to_be_visible().await?;

    // Toggle switch is visible
    actor.expect(sleep::toggle()).to_be_visible().await?;

    // Custom h/m/s inputs are hidden by default
    actor.expect(sleep::hours_input()).not().to_be_visible().await?;
    actor.expect(sleep::minutes_input()).not().to_be_visible().await?;
    actor.expect(sleep::seconds_input()).not().to_be_visible().await?;

    // Clicking "custom" reveals h/m/s inputs
    actor.locate(sleep::custom_button()).await.click(None).await?;
    actor.expect(sleep::hours_input()).to_be_visible().await?;
    actor.expect(sleep::minutes_input()).to_be_visible().await?;
    actor.expect(sleep::seconds_input()).to_be_visible().await?;

    // Clicking a preset hides h/m/s inputs
    actor.locate(sleep::preset_button("5m")).await.click(None).await?;
    actor.expect(sleep::hours_input()).not().to_be_visible().await?;

    Ok(())
}
