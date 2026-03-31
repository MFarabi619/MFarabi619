use crate::app::{App, AppAction};

#[derive(Clone, Copy, Debug)]
pub enum AppKeyCode {
    Esc,
    Enter,
    Backspace,
    Tab,
    #[cfg(not(target_arch = "wasm32"))]
    BackTab,
    Up,
    Down,
    Left,
    Right,
    Char(char),
}

#[derive(Clone, Copy, Debug)]
pub struct AppKeyEvent {
    pub code: AppKeyCode,
    pub shift: bool,
}

pub fn map_key_event_to_action(app: &App, app_key_event: AppKeyEvent) -> Option<AppAction> {
    if app.api_base_url_editor_open {
        return match app_key_event.code {
            AppKeyCode::Esc => Some(AppAction::CloseApiBaseUrlEditor),
            AppKeyCode::Enter => Some(AppAction::ApplyApiBaseUrlEditor),
            AppKeyCode::Backspace => Some(AppAction::ApiBaseUrlEditorBackspace),
            AppKeyCode::Char(character) => Some(AppAction::ApiBaseUrlEditorInputChar(character)),
            _ => None,
        };
    }

    if app.command_palette_open {
        return match app_key_event.code {
            AppKeyCode::Esc => Some(AppAction::CloseCommandPalette),
            AppKeyCode::Enter => Some(AppAction::CommandPaletteExecute),
            AppKeyCode::Backspace => Some(AppAction::CommandPaletteBackspace),
            AppKeyCode::Up | AppKeyCode::Char('k') => Some(AppAction::CommandPaletteSelectUp),
            AppKeyCode::Down | AppKeyCode::Char('j') => Some(AppAction::CommandPaletteSelectDown),
            AppKeyCode::Char(character) => Some(AppAction::CommandPaletteInputChar(character)),
            _ => None,
        };
    }

    match app_key_event.code {
        AppKeyCode::Char('q') => Some(AppAction::Quit),
        AppKeyCode::Char('?') => Some(AppAction::OpenCommandPalette),
        AppKeyCode::Tab if app_key_event.shift => Some(AppAction::PreviousPane),
        AppKeyCode::Tab => Some(AppAction::NextPane),
        #[cfg(not(target_arch = "wasm32"))]
        AppKeyCode::BackTab => Some(AppAction::PreviousPane),
        AppKeyCode::Up | AppKeyCode::Char('k') => Some(AppAction::MoveSelectionUp),
        AppKeyCode::Down | AppKeyCode::Char('j') => Some(AppAction::MoveSelectionDown),
        AppKeyCode::Left | AppKeyCode::Char('h') => Some(AppAction::SelectPreviousMeasurementTab),
        AppKeyCode::Right | AppKeyCode::Char('l') => Some(AppAction::SelectNextMeasurementTab),
        AppKeyCode::Char('r') => Some(AppAction::RefreshFileSystem),
        AppKeyCode::Char('s') => Some(AppAction::ScanNetwork),
        AppKeyCode::Char('i') => Some(AppAction::OpenApiBaseUrlEditor),
        _ => None,
    }
}

#[cfg(not(target_arch = "wasm32"))]
use crossterm::event::{
    KeyCode, KeyEvent as NativeKeyEvent, MouseEvent as NativeMouseEvent, MouseEventKind,
};

#[cfg(not(target_arch = "wasm32"))]
pub fn app_key_event_from_native(key_event: NativeKeyEvent) -> Option<AppKeyEvent> {
    let app_key_code = match key_event.code {
        KeyCode::Esc => AppKeyCode::Esc,
        KeyCode::Enter => AppKeyCode::Enter,
        KeyCode::Backspace => AppKeyCode::Backspace,
        KeyCode::Tab => AppKeyCode::Tab,
        KeyCode::BackTab => AppKeyCode::BackTab,
        KeyCode::Up => AppKeyCode::Up,
        KeyCode::Down => AppKeyCode::Down,
        KeyCode::Left => AppKeyCode::Left,
        KeyCode::Right => AppKeyCode::Right,
        KeyCode::Char(character) => AppKeyCode::Char(character),
        _ => return None,
    };

    Some(AppKeyEvent {
        code: app_key_code,
        shift: false,
    })
}

#[cfg(not(target_arch = "wasm32"))]
pub fn map_native_mouse_event(mouse_event: NativeMouseEvent) -> Option<AppAction> {
    match mouse_event.kind {
        MouseEventKind::Moved | MouseEventKind::Drag(_) | MouseEventKind::Down(_) => {
            Some(AppAction::MouseHover {
                column: mouse_event.column,
                row: mouse_event.row,
            })
        }
        _ => None,
    }
}

#[cfg(target_arch = "wasm32")]
use ratzilla::event::{
    KeyCode, KeyEvent as WebKeyEvent, MouseEvent as WebMouseEvent, MouseEventKind,
};

#[cfg(target_arch = "wasm32")]
pub fn app_key_event_from_web(key_event: WebKeyEvent) -> Option<AppKeyEvent> {
    let app_key_code = match key_event.code {
        KeyCode::Esc => AppKeyCode::Esc,
        KeyCode::Enter => AppKeyCode::Enter,
        KeyCode::Backspace => AppKeyCode::Backspace,
        KeyCode::Tab => AppKeyCode::Tab,
        KeyCode::Up => AppKeyCode::Up,
        KeyCode::Down => AppKeyCode::Down,
        KeyCode::Left => AppKeyCode::Left,
        KeyCode::Right => AppKeyCode::Right,
        KeyCode::Char(character) => AppKeyCode::Char(character),
        _ => return None,
    };

    Some(AppKeyEvent {
        code: app_key_code,
        shift: key_event.shift,
    })
}

#[cfg(target_arch = "wasm32")]
pub fn map_web_mouse_event(mouse_event: WebMouseEvent) -> Option<AppAction> {
    match mouse_event.event {
        MouseEventKind::Moved | MouseEventKind::Pressed | MouseEventKind::Released => {
            let column = u16::try_from(mouse_event.x).ok()?;
            let row = u16::try_from(mouse_event.y).ok()?;
            Some(AppAction::MouseHover { column, row })
        }
        MouseEventKind::Unidentified => None,
    }
}
