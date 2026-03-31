use ratatui::layout::{Position, Rect};
#[cfg(target_arch = "wasm32")]
use ratatui::widgets::ListState;
use ratatui::widgets::TableState;

#[cfg(not(target_arch = "wasm32"))]
use {
    std::sync::mpsc::{self, Receiver, Sender},
    throbber_widgets_tui::ThrobberState,
    tui_tree_widget::TreeState,
};

const DEFAULT_API_BASE_URL: &str = "http://10.0.0.95";
const DEFAULT_SD_TOTAL_BYTES: u64 = 4 * 1024 * 1024;
const DEFAULT_LITTLEFS_TOTAL_BYTES: u64 = 1024 * 1024;

#[derive(Clone, Debug, serde::Deserialize)]
pub struct FileSystemEntry {
    pub name: String,
    pub size: u64,
}

#[derive(Clone, Debug, Default)]
pub enum FileSystemLoadState {
    #[default]
    Idle,
    Loading,
    Loaded,
    Error(String),
}

#[derive(Clone, Debug, serde::Deserialize)]
pub struct WirelessNetworkEntry {
    pub ssid: String,
    pub rssi: i32,
    pub channel: u32,
    pub encryption: String,
}

#[derive(Clone, Debug, serde::Deserialize)]
pub struct WirelessStatus {
    pub connected: bool,
    pub sta_ssid: String,
    pub sta_ipv4: String,
    pub ap_ipv4: String,
}

#[derive(Clone, Debug, Default)]
pub enum NetworkScanLoadState {
    #[default]
    Idle,
    Loading,
    Loaded,
    Error(String),
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum FocusArea {
    #[default]
    Measurements,
    Network,
    FileSystem,
}

impl FocusArea {
    pub fn next(self) -> Self {
        match self {
            Self::Measurements => Self::Network,
            Self::Network => Self::FileSystem,
            Self::FileSystem => Self::Measurements,
        }
    }

    pub fn previous(self) -> Self {
        match self {
            Self::Measurements => Self::FileSystem,
            Self::Network => Self::Measurements,
            Self::FileSystem => Self::Network,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum MeasurementTab {
    #[default]
    Voltage,
    Current,
}

impl MeasurementTab {
    pub fn next(self) -> Self {
        match self {
            Self::Voltage => Self::Current,
            Self::Current => Self::Voltage,
        }
    }

    pub fn previous(self) -> Self {
        self.next()
    }

    pub fn index(self) -> usize {
        match self {
            Self::Voltage => 0,
            Self::Current => 1,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AppAction {
    Quit,
    NextPane,
    PreviousPane,
    FocusMeasurementsPane,
    FocusNetworkPane,
    FocusFileSystemPane,
    MoveSelectionUp,
    MoveSelectionDown,
    SelectPreviousMeasurementTab,
    SelectNextMeasurementTab,
    RefreshFileSystem,
    ScanNetwork,
    OpenCommandPalette,
    CloseCommandPalette,
    CommandPaletteInputChar(char),
    CommandPaletteBackspace,
    CommandPaletteSelectUp,
    CommandPaletteSelectDown,
    CommandPaletteExecute,
    OpenApiBaseUrlEditor,
    CloseApiBaseUrlEditor,
    ApiBaseUrlEditorInputChar(char),
    ApiBaseUrlEditorBackspace,
    ApplyApiBaseUrlEditor,
    MouseHover { column: u16, row: u16 },
    Noop,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AppEffect {
    RefreshFileSystem,
    ScanNetwork,
}

#[derive(Clone, Copy, Debug)]
pub struct DashboardAreas {
    pub measurements_area: Rect,
    pub network_area: Rect,
    pub filesystem_area: Rect,
}

impl Default for DashboardAreas {
    fn default() -> Self {
        Self {
            measurements_area: Rect::ZERO,
            network_area: Rect::ZERO,
            filesystem_area: Rect::ZERO,
        }
    }
}

impl DashboardAreas {
    pub fn focus_area_at(self, column: u16, row: u16) -> Option<FocusArea> {
        let position = Position::new(column, row);
        if self.measurements_area.contains(position) {
            return Some(FocusArea::Measurements);
        }
        if self.network_area.contains(position) {
            return Some(FocusArea::Network);
        }
        if self.filesystem_area.contains(position) {
            return Some(FocusArea::FileSystem);
        }
        None
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CommandPaletteGroup {
    Actions,
    Navigate,
}

pub struct CommandPaletteItem {
    pub group: CommandPaletteGroup,
    pub icon: &'static str,
    pub label: &'static str,
    pub shortcut: &'static str,
    pub keywords: &'static str,
    pub action: AppAction,
}

pub const COMMAND_PALETTE_ITEMS: [CommandPaletteItem; 10] = [
    CommandPaletteItem {
        group: CommandPaletteGroup::Actions,
        icon: "⚗",
        label: "Sample Voltage",
        shortcut: "Ctrl+Enter",
        keywords: "sample voltage csv",
        action: AppAction::Noop,
    },
    CommandPaletteItem {
        group: CommandPaletteGroup::Actions,
        icon: "⚗",
        label: "Sample Current",
        shortcut: "Ctrl+Enter",
        keywords: "sample current csv",
        action: AppAction::Noop,
    },
    CommandPaletteItem {
        group: CommandPaletteGroup::Actions,
        icon: "⌗",
        label: "Set Device API URL",
        shortcut: "i",
        keywords: "api url ip host esp32",
        action: AppAction::OpenApiBaseUrlEditor,
    },
    CommandPaletteItem {
        group: CommandPaletteGroup::Actions,
        icon: "⇪",
        label: "Upload File to SD",
        shortcut: "",
        keywords: "upload file filesystem sd",
        action: AppAction::Noop,
    },
    CommandPaletteItem {
        group: CommandPaletteGroup::Actions,
        icon: "◉",
        label: "Scan Networks",
        shortcut: "s",
        keywords: "scan networks wifi",
        action: AppAction::ScanNetwork,
    },
    CommandPaletteItem {
        group: CommandPaletteGroup::Actions,
        icon: "↻",
        label: "Refresh Filesystems",
        shortcut: "r",
        keywords: "refresh filesystems sd littlefs",
        action: AppAction::RefreshFileSystem,
    },
    CommandPaletteItem {
        group: CommandPaletteGroup::Navigate,
        icon: "⚡",
        label: "Measurements",
        shortcut: "",
        keywords: "measurements voltage current",
        action: AppAction::FocusMeasurementsPane,
    },
    CommandPaletteItem {
        group: CommandPaletteGroup::Navigate,
        icon: "📡",
        label: "Networking",
        shortcut: "",
        keywords: "networking wifi scan",
        action: AppAction::FocusNetworkPane,
    },
    CommandPaletteItem {
        group: CommandPaletteGroup::Navigate,
        icon: "💾",
        label: "Filesystem",
        shortcut: "",
        keywords: "filesystem sd littlefs files",
        action: AppAction::FocusFileSystemPane,
    },
    CommandPaletteItem {
        group: CommandPaletteGroup::Actions,
        icon: "{}",
        label: "Open API",
        shortcut: "Ctrl+/",
        keywords: "api cloudevents",
        action: AppAction::Noop,
    },
];

#[derive(Debug, serde::Deserialize)]
pub(super) struct ApiEnvelope<T> {
    pub(super) data: T,
}

#[derive(Debug, serde::Deserialize)]
pub(super) struct WirelessScanData {
    pub(super) networks: Vec<WirelessNetworkEntry>,
}

#[cfg(not(target_arch = "wasm32"))]
pub(super) enum NativeBackgroundMessage {
    FileSystem(Result<Vec<FileSystemEntry>, String>),
    WirelessStatus(Result<WirelessStatus, String>),
    WirelessScan(Result<Vec<WirelessNetworkEntry>, String>),
}

pub struct App {
    pub(super) exit: bool,
    pub measurement_tab: MeasurementTab,
    pub file_system_entries: Vec<FileSystemEntry>,
    pub file_system_load_state: FileSystemLoadState,
    pub wireless_status: Option<WirelessStatus>,
    pub wireless_networks: Vec<WirelessNetworkEntry>,
    pub network_scan_load_state: NetworkScanLoadState,
    pub focus_area: FocusArea,
    #[cfg(target_arch = "wasm32")]
    pub file_system_list_state: ListState,
    pub network_table_state: TableState,
    pub command_palette_open: bool,
    pub command_palette_query: String,
    pub(super) command_palette_selected_index: usize,
    pub api_base_url: String,
    pub api_base_url_editor_open: bool,
    pub api_base_url_editor_buffer: String,
    pub dashboard_areas: DashboardAreas,
    pub sd_total_bytes: u64,
    pub littlefs_total_bytes: u64,
    #[cfg(not(target_arch = "wasm32"))]
    pub file_system_tree_state: TreeState<String>,
    #[cfg(not(target_arch = "wasm32"))]
    pub file_system_throbber_state: ThrobberState,
    #[cfg(not(target_arch = "wasm32"))]
    pub network_throbber_state: ThrobberState,
    #[cfg(not(target_arch = "wasm32"))]
    pub(super) native_background_sender: Sender<NativeBackgroundMessage>,
    #[cfg(not(target_arch = "wasm32"))]
    pub(super) native_background_receiver: Receiver<NativeBackgroundMessage>,
}

impl Default for App {
    fn default() -> Self {
        #[cfg(not(target_arch = "wasm32"))]
        let (native_background_sender, native_background_receiver) = mpsc::channel();

        Self {
            exit: false,
            measurement_tab: MeasurementTab::Voltage,
            file_system_entries: Vec::new(),
            file_system_load_state: FileSystemLoadState::Idle,
            wireless_status: None,
            wireless_networks: Vec::new(),
            network_scan_load_state: NetworkScanLoadState::Idle,
            focus_area: FocusArea::Measurements,
            #[cfg(target_arch = "wasm32")]
            file_system_list_state: ListState::default(),
            network_table_state: TableState::default(),
            command_palette_open: false,
            command_palette_query: String::new(),
            command_palette_selected_index: 0,
            api_base_url: DEFAULT_API_BASE_URL.to_owned(),
            api_base_url_editor_open: false,
            api_base_url_editor_buffer: String::new(),
            dashboard_areas: DashboardAreas::default(),
            sd_total_bytes: DEFAULT_SD_TOTAL_BYTES,
            littlefs_total_bytes: DEFAULT_LITTLEFS_TOTAL_BYTES,
            #[cfg(not(target_arch = "wasm32"))]
            file_system_tree_state: TreeState::default(),
            #[cfg(not(target_arch = "wasm32"))]
            file_system_throbber_state: ThrobberState::default(),
            #[cfg(not(target_arch = "wasm32"))]
            network_throbber_state: ThrobberState::default(),
            #[cfg(not(target_arch = "wasm32"))]
            native_background_sender,
            #[cfg(not(target_arch = "wasm32"))]
            native_background_receiver,
        }
    }
}

impl App {
    pub fn new() -> Self {
        Self::default()
    }

    #[cfg(not(target_arch = "wasm32"))]
    pub fn tick_native(&mut self) {
        self.file_system_throbber_state.calc_next();
        self.network_throbber_state.calc_next();
    }

    #[cfg(not(target_arch = "wasm32"))]
    pub fn should_exit(&self) -> bool {
        self.exit
    }

    pub fn endpoint(&self, path: &str) -> String {
        format!("{}{}", self.api_base_url.trim_end_matches('/'), path)
    }

    pub fn sd_used_bytes(&self) -> u64 {
        self.file_system_entries
            .iter()
            .filter(|file_system_entry| !file_system_entry.name.starts_with("littlefs/"))
            .map(|file_system_entry| file_system_entry.size)
            .sum()
    }

    pub fn littlefs_used_bytes(&self) -> u64 {
        self.file_system_entries
            .iter()
            .filter(|file_system_entry| file_system_entry.name.starts_with("littlefs/"))
            .map(|file_system_entry| file_system_entry.size)
            .sum()
    }

    pub fn storage_ratio(used_bytes: u64, total_bytes: u64) -> f64 {
        if total_bytes == 0 {
            return 0.0;
        }
        (used_bytes as f64 / total_bytes as f64).clamp(0.0, 1.0)
    }

    pub fn format_file_size(bytes: u64) -> String {
        if bytes < 1024 {
            return format!("{bytes} B");
        }
        let kibibytes = bytes as f64 / 1024.0;
        if kibibytes < 1024.0 {
            return format!("{kibibytes:.1} KB");
        }
        let mebibytes = kibibytes / 1024.0;
        format!("{mebibytes:.2} MB")
    }

    pub fn split_file_system_entries(&self) -> (Vec<&FileSystemEntry>, Vec<&FileSystemEntry>) {
        let mut sd_entries = Vec::new();
        let mut littlefs_entries = Vec::new();
        for file_system_entry in &self.file_system_entries {
            if file_system_entry.name.starts_with("littlefs/") {
                littlefs_entries.push(file_system_entry);
            } else {
                sd_entries.push(file_system_entry);
            }
        }
        (sd_entries, littlefs_entries)
    }

    pub fn display_file_name(file_system_entry: &FileSystemEntry, source_prefix: &str) -> String {
        file_system_entry
            .name
            .strip_prefix(source_prefix)
            .unwrap_or(&file_system_entry.name)
            .to_owned()
    }

    #[cfg(target_arch = "wasm32")]
    pub fn file_system_render_row_count(&self) -> usize {
        let (sd_entries, littlefs_entries) = self.split_file_system_entries();
        match self.file_system_load_state {
            FileSystemLoadState::Loaded => {
                2 + sd_entries.len().max(1) + 1 + 2 + littlefs_entries.len().max(1)
            }
            _ => 6,
        }
    }
}
