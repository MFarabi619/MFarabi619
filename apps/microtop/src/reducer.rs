use crate::app::{App, AppAction, AppEffect};

pub fn reduce(app: &mut App, action: AppAction) -> (Option<AppAction>, Option<AppEffect>) {
    app.reduce_action(action)
}
