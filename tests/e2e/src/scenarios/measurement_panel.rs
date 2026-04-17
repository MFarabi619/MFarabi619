use crate::actor::Actor;
use crate::locators::measurement;

pub async fn run(actor: &Actor) -> crate::actor::Result {
    // Panel and tabs are visible
    actor.expect(measurement::root()).to_be_visible().await?;
    actor.expect(measurement::temp_humidity_tab()).to_be_visible().await?;
    actor.expect(measurement::voltage_tab()).to_be_visible().await?;
    actor.expect(measurement::co2_tab()).to_be_visible().await?;

    // Sample and CSV buttons are visible
    actor.expect(measurement::sample_button()).to_be_visible().await?;
    actor.expect(measurement::csv_button()).to_be_visible().await?;

    // Clicking tabs switches content
    actor.locate(measurement::voltage_tab()).await.click(None).await?;
    actor.expect(measurement::voltage_tab()).to_be_visible().await?;

    actor.locate(measurement::co2_tab()).await.click(None).await?;
    actor.expect(measurement::co2_tab()).to_be_visible().await?;

    // Switch back to temp/humidity
    actor.locate(measurement::temp_humidity_tab()).await.click(None).await?;
    actor.expect(measurement::temp_humidity_tab()).to_be_visible().await?;

    Ok(())
}
