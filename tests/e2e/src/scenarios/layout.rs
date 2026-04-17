use crate::actor::Actor;
use crate::locators::{footer, navbar};

pub async fn run(actor: &Actor) -> crate::actor::Result {
    actor.expect(navbar::root()).to_be_visible().await?;
    actor.expect(navbar::logo()).to_contain_text("Apidae Systems").await?;
    actor.expect(navbar::search_button()).to_be_visible().await?;

    actor.expect(footer::root()).to_be_visible().await?;
    actor.expect(footer::github_link()).to_be_visible().await?;
    actor.expect(footer::linkedin_link()).to_be_visible().await?;
    actor.expect(footer::website_link()).to_be_visible().await?;

    Ok(())
}
