use crate::actor::Actor;
use crate::locators::{navbar, network_sheet};

pub async fn run(actor: &Actor) -> crate::actor::Result {
    actor.locate(navbar::wifi_button()).await.click(None).await?;
    actor.expect(network_sheet::root()).to_be_visible().await?;

    // Form elements present
    actor.expect(network_sheet::ssid_input()).to_be_visible().await?;
    actor.expect(network_sheet::password_input()).to_be_visible().await?;
    actor.expect(network_sheet::connect_button()).to_be_visible().await?;
    actor.expect(network_sheet::results_region()).to_be_visible().await?;

    // Connect button disabled when SSID empty
    actor.expect(network_sheet::connect_button()).to_be_disabled().await?;

    // Close it so the rest of the journey keeps a clean surface.
    actor.locate(network_sheet::close_button()).await.click(None).await?;
    actor.expect(network_sheet::root()).to_be_hidden().await?;

    Ok(())
}
