use crate::actor::Actor;
use crate::locators::flash;

pub async fn run(actor: &Actor) -> crate::actor::Result {
    // Panel is visible with heading
    actor.expect(flash::root()).to_be_visible().await?;
    actor.expect(flash::heading()).to_be_visible().await?;

    // Connect button is visible before connection
    actor.expect(flash::connect_button()).to_be_visible().await?;

    // Flash/monitor/disconnect are not visible before connection
    actor.expect(flash::disconnect_button()).not().to_be_visible().await?;
    actor.expect(flash::flash_button()).not().to_be_visible().await?;
    actor.expect(flash::monitor_button()).not().to_be_visible().await?;
    actor.expect(flash::firmware_section()).not().to_be_visible().await?;

    Ok(())
}
