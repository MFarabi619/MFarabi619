use std::{cell::Cell, sync::Arc};

use oxidros::{
    msg::{interfaces::rcl_interfaces::msg::Log, msg::RosString},
    prelude::*,
};
use tracing::Subscriber;
use tracing_subscriber::Layer;

use crate::now_stamp;

// TODO(rosout): oxidros leaves /rosout publishing as a future feature in its
// ZenohLayer (oxidros-zenoh/src/logger.rs). Retire this module once oxidros
// emits rcl_interfaces/msg/Log on /rosout itself.

thread_local! {
    static PUBLISHING: Cell<bool> = const { Cell::new(false) };
}

struct RosoutLayer {
    logger: String,
    publisher: Publisher<Log>,
}

impl RosoutLayer {
    fn publish(&self, event: &tracing::Event<'_>) -> Option<()> {
        let metadata = event.metadata();
        let mut message = MessageVisitor(String::new());
        event.record(&mut message);

        let (sec, nanosec) = now_stamp();
        let mut log = Log::new()?;
        log.stamp.sec = sec;
        log.stamp.nanosec = nanosec;
        log.level = match *metadata.level() {
            tracing::Level::ERROR => Log::ERROR,
            tracing::Level::WARN => Log::WARN,
            tracing::Level::INFO => Log::INFO,
            _ => Log::DEBUG,
        };
        log.name = RosString::new(&self.logger)?;
        log.msg = RosString::new(&message.0)?;
        log.file = RosString::new(metadata.file().unwrap_or_default())?;
        log.function = RosString::new(metadata.target())?;
        log.line = metadata.line().unwrap_or_default();
        self.publisher.send(&log).ok()?;
        Some(())
    }
}

impl<S: Subscriber> Layer<S> for RosoutLayer {
    fn on_event(
        &self,
        event: &tracing::Event<'_>,
        _ctx: tracing_subscriber::layer::Context<'_, S>,
    ) {
        PUBLISHING.with(|guard| {
            if guard.replace(true) {
                return;
            }
            let _ = self.publish(event);
            guard.set(false);
        });
    }
}

struct MessageVisitor(String);

impl tracing::field::Visit for MessageVisitor {
    fn record_debug(&mut self, field: &tracing::field::Field, value: &dyn std::fmt::Debug) {
        if field.name() == "message" {
            self.0 = format!("{value:?}");
        }
    }
}

pub fn init_logging(
    context: &Arc<Context>,
    logger: &str,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let node = context.create_node("rosout", None)?;
    let publisher = node.create_publisher::<Log>("/rosout", None)?;
    LoggingBuilder::new(logger)
        .with_layer(RosoutLayer {
            logger: logger.to_string(),
            publisher,
        })
        .with_fmt_layer()
        .init();
    Ok(())
}
