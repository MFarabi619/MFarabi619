use std::time::Duration;

use crate::actor::Actor;
use crate::locators::{filesystem, flash, measurement, navbar, terminal, url_bar};

pub async fn run(actor: &Actor) -> crate::actor::Result {
    actor.expect(navbar::logo()).to_contain_text("Apidae Systems").await?;
    actor.expect(navbar::search_button()).to_be_visible().await?;
    actor.expect(navbar::wifi_button()).to_be_visible().await?;

    actor
        .expect(url_bar::connection_status())
        .with_timeout(Duration::from_secs(15))
        .not()
        .to_contain_text("POLLING")
        .await?;

    actor.expect(navbar::chip_badge()).to_contain_text_regex("ESP32").await?;
    actor
        .expect(navbar::memory_badge())
        .to_contain_text_regex(r"\d+/\d+ KB")
        .await?;
    actor.expect(navbar::skeleton_badges()).not().to_be_visible().await?;

    actor.expect(measurement::root()).to_be_visible().await?;
    actor.expect(measurement::temp_humidity_tab()).to_be_visible().await?;
    actor.expect(measurement::voltage_tab()).to_be_visible().await?;
    actor.expect(measurement::co2_tab()).to_be_visible().await?;
    actor.expect(measurement::sample_button()).to_be_visible().await?;
    actor.expect(measurement::csv_button()).to_be_visible().await?;
    actor.expect(filesystem::root()).to_be_visible().await?;
    actor.expect(terminal::root()).to_be_visible().await?;
    actor.expect(flash::root()).to_be_visible().await?;

    Ok(())
}
