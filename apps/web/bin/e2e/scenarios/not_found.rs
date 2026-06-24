use crate::actor::Actor;
use crate::locators::not_found;
use crate::tasks::{base_url, Navigate};

pub async fn run(actor: &Actor) -> crate::actor::Result {
    actor.attempts_to(Navigate::to("/this-does-not-exist")).await?;
    actor.expect(not_found::heading()).to_contain_text("404").await?;
    actor.expect(not_found::subheading()).to_contain_text("Page Not Found").await?;

    actor.locate(not_found::back_home_button()).await.click(None).await?;
    actor.expect_page().to_have_url_regex(&format!("^{}/?$", regex::escape(&base_url()))).await?;

    Ok(())
}
