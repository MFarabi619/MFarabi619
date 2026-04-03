use async_trait::async_trait;
use loco_openapi::prelude::*;
use loco_rs::{
    Result,
    app::{AppContext, Hooks, Initializer},
    bgworker::{BackgroundWorker, Queue},
    boot::{BootResult, StartMode, create_app},
    config::Config,
    controller::AppRoutes,
    db::{self, truncate_table},
    environment::Environment,
    task::Tasks,
};
use migration::Migrator;
use std::path::Path;

#[allow(unused_imports)]
use crate::{
    controllers, initializers, models::_entities::users, tasks, workers::downloader::DownloadWorker,
};

pub struct App;
#[async_trait]
impl Hooks for App {
    fn app_name() -> &'static str {
        env!("CARGO_CRATE_NAME")
    }

    fn app_version() -> String {
        format!(
            "{} ({})",
            env!("CARGO_PKG_VERSION"),
            option_env!("BUILD_SHA")
                .or(option_env!("GITHUB_SHA"))
                .unwrap_or("dev")
        )
    }

    async fn boot(
        mode: StartMode,
        environment: &Environment,
        config: Config,
    ) -> Result<BootResult> {
        create_app::<Self, Migrator>(mode, environment, config).await
    }

    async fn initializers(_ctx: &AppContext) -> Result<Vec<Box<dyn Initializer>>> {
        Ok(vec![
            Box::new(initializers::view_engine::ViewEngineInitializer),
            Box::new(loco_openapi::OpenapiInitializerWithSetup::new(
                |_ctx| {
                    #[derive(OpenApi)]
                    #[openapi(
                    modifiers(&SecurityAddon),
                    info(
                        title = "🧩 Microvisor Systems OpenAPI Spec 🧩",
                        description = "Beep Boop 🤖"
                    )
                )]
                    struct ApiDoc;
                    ApiDoc::openapi()
                },
                None, // When using automatic schema collection only
                      // When using manual schema collection
                      // Manual schema collection can also be used at the same time as automatic schema collection
                      // Some(vec![controllers::album::api_routes()]),
            )),
        ])
    }

    fn routes(_ctx: &AppContext) -> AppRoutes {
        AppRoutes::with_default_routes() // controller routes below
            .add_route(controllers::auth::routes())
    }

    async fn after_routes(router: axum::Router, _ctx: &AppContext) -> Result<axum::Router> {
        async fn scalar_ui() -> axum::response::Html<String> {
            let cfg = serde_json::json!({
              "isLoading": true,
              "theme": "deepSpace",
              "hideClientButton": true,
              "defaultOpenAllTags": true,
              "expandAllResponses": true,
              "favicon": "/nix-mfarabi.svg" ,
              "expandAllModelSections": true,
              "url": "/api-docs/openapi.json",
            });

            axum::response::Html(scalar_api_reference::scalar_html_default(&cfg))
        }

        Ok(router.route("/scalar", axum::routing::get(scalar_ui)))
    }

    async fn connect_workers(ctx: &AppContext, queue: &Queue) -> Result<()> {
        queue.register(DownloadWorker::build(ctx)).await?;
        Ok(())
    }

    #[allow(unused_variables)]
    fn register_tasks(tasks: &mut Tasks) {
        tasks.register(tasks::build::Build);
        tasks.register(tasks::flash::Flash);
        tasks.register(tasks::upload::Upload);
        // tasks-inject (do not remove)
    }
    async fn truncate(ctx: &AppContext) -> Result<()> {
        truncate_table(&ctx.db, users::Entity).await?;
        Ok(())
    }
    async fn seed(ctx: &AppContext, base: &Path) -> Result<()> {
        db::seed::<users::ActiveModel>(&ctx.db, &base.join("users.yaml").display().to_string())
            .await?;
        Ok(())
    }
}
