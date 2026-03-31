use crate::{
    app::{App, AppAction, AppEffect},
    reducer,
};

#[cfg(not(target_arch = "wasm32"))]
pub fn dispatch_native_action(app: &mut App, action: AppAction) {
    let mut pending_action = Some(action);
    while let Some(current_action) = pending_action {
        let (next_action, effect) = reducer::reduce(app, current_action);
        execute_native_effect(app, effect);
        pending_action = next_action;
    }
}

#[cfg(not(target_arch = "wasm32"))]
fn execute_native_effect(app: &mut App, effect: Option<AppEffect>) {
    match effect {
        Some(AppEffect::RefreshFileSystem) => app.start_file_system_refresh_native(),
        Some(AppEffect::ScanNetwork) => {
            app.start_wireless_status_refresh_native();
            app.start_network_scan_native();
        }
        None => {}
    }
}

#[cfg(target_arch = "wasm32")]
use std::{cell::RefCell, rc::Rc};

#[cfg(target_arch = "wasm32")]
pub fn dispatch_web_action(app_state: &Rc<RefCell<App>>, action: AppAction) {
    let mut pending_action = Some(action);
    while let Some(current_action) = pending_action {
        let (next_action, effect) = reducer::reduce(&mut app_state.borrow_mut(), current_action);
        execute_web_effect(app_state, effect);
        pending_action = next_action;
    }
}

#[cfg(target_arch = "wasm32")]
fn execute_web_effect(app_state: &Rc<RefCell<App>>, effect: Option<AppEffect>) {
    match effect {
        Some(AppEffect::RefreshFileSystem) => App::start_file_system_refresh_web(app_state.clone()),
        Some(AppEffect::ScanNetwork) => {
            App::start_wireless_status_refresh_web(app_state.clone());
            App::start_network_scan_web(app_state.clone());
        }
        None => {}
    }
}
