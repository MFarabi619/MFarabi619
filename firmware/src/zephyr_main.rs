use embassy_executor::Spawner;
use embassy_time::{Duration, Timer};
use log_04::info;
use static_cell::StaticCell;
use zephyr::embassy::Executor;

static EXECUTOR: StaticCell<Executor> = StaticCell::new();

#[unsafe(no_mangle)]
extern "C" fn rust_main() {
    unsafe {
        zephyr::set_logger().unwrap();
    }

    info!("Microvisor Rust starting on Zephyr");

    let executor = EXECUTOR.init(Executor::new());
    executor.run(|spawner| {
        spawner.spawn(main_task(spawner).unwrap());
    })
}

#[embassy_executor::task]
async fn main_task(_spawner: Spawner) {
    info!("Embassy executor running");

    loop {
        info!("heartbeat");
        Timer::after(Duration::from_secs(1)).await;
    }
}
