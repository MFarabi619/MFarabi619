use std::time::Duration;

use crate::actor::Actor;
use crate::locators::url_bar;

pub async fn run(actor: &Actor) -> crate::actor::Result {
    actor.expect(url_bar::hostname_input()).to_have_value("ceratina.local").await?;
    actor.expect(url_bar::connection_status()).to_be_visible().await?;
    actor
        .expect(url_bar::connection_status())
        .with_timeout(Duration::from_secs(15))
        .not()
        .to_contain_text("POLLING")
        .await?;
    actor
        .expect(url_bar::live_status())
        .to_contain_text_regex(r"(LIVE|\d+\.\d+\.\d+\.\d+)")
        .await?;

    Ok(())
}
