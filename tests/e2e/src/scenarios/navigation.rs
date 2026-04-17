use crate::actor::Actor;
use crate::locators::navbar;
use crate::tasks::base_url;

pub async fn run(actor: &Actor) -> crate::actor::Result {
    actor.expect_page().to_have_url_regex(&format!("^{}.*", regex::escape(&base_url()))).await?;
    actor.expect(navbar::root()).to_be_visible().await?;
    Ok(())
}
