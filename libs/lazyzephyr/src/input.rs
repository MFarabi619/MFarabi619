#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InputMode { Nav, Search }

#[derive(Debug, Clone, Copy)]
#[allow(dead_code)]
pub enum Key {
    Char(char),
    Ctrl(char),
    Enter,
    Esc,
    Tab,
    BackTab,
    Up, Down, Left, Right,
    Backspace,
    Click(u16, u16),
    ScrollUp(u16, u16),
    ScrollDown(u16, u16),
    Unknown,
}
