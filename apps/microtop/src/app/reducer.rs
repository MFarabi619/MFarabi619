use super::{App, AppAction, AppEffect, COMMAND_PALETTE_ITEMS, FocusArea};

impl App {
    pub fn close_command_palette(&mut self) {
        self.command_palette_open = false;
        self.command_palette_query.clear();
        self.command_palette_selected_index = 0;
    }

    pub fn open_command_palette(&mut self) {
        self.command_palette_open = true;
        self.command_palette_query.clear();
        self.command_palette_selected_index = 0;
    }

    pub fn open_api_base_url_editor(&mut self) {
        self.api_base_url_editor_open = true;
        self.api_base_url_editor_buffer = self.api_base_url.clone();
    }

    pub fn close_api_base_url_editor(&mut self) {
        self.api_base_url_editor_open = false;
        self.api_base_url_editor_buffer.clear();
    }

    fn apply_api_base_url_editor(&mut self) {
        let trimmed_value = self.api_base_url_editor_buffer.trim();
        if trimmed_value.is_empty() {
            self.close_api_base_url_editor();
            return;
        }

        self.api_base_url =
            if trimmed_value.starts_with("http://") || trimmed_value.starts_with("https://") {
                trimmed_value.trim_end_matches('/').to_owned()
            } else {
                format!("http://{}", trimmed_value.trim_end_matches('/'))
            };

        self.close_api_base_url_editor();
    }

    pub fn filtered_command_item_indices(&self) -> Vec<usize> {
        let query = self.command_palette_query.trim().to_lowercase();
        COMMAND_PALETTE_ITEMS
            .iter()
            .enumerate()
            .filter_map(|(index, command_palette_item)| {
                if query.is_empty() {
                    return Some(index);
                }

                let haystack = format!(
                    "{} {} {}",
                    command_palette_item.label,
                    command_palette_item.keywords,
                    command_palette_item.shortcut
                )
                .to_lowercase();

                if haystack.contains(&query) {
                    Some(index)
                } else {
                    None
                }
            })
            .collect()
    }

    pub fn command_palette_selected_index(&self) -> usize {
        self.command_palette_selected_index
    }

    fn normalize_command_palette_selection(&mut self) {
        let filtered_length = self.filtered_command_item_indices().len();
        if filtered_length == 0 {
            self.command_palette_selected_index = 0;
            return;
        }

        if self.command_palette_selected_index >= filtered_length {
            self.command_palette_selected_index = filtered_length - 1;
        }
    }

    fn move_command_palette_selection_previous(&mut self) {
        let filtered_length = self.filtered_command_item_indices().len();
        if filtered_length == 0 {
            self.command_palette_selected_index = 0;
            return;
        }

        self.command_palette_selected_index =
            Self::wrapped_previous_index(self.command_palette_selected_index, filtered_length);
    }

    fn move_command_palette_selection_next(&mut self) {
        let filtered_length = self.filtered_command_item_indices().len();
        if filtered_length == 0 {
            self.command_palette_selected_index = 0;
            return;
        }

        self.command_palette_selected_index =
            Self::wrapped_next_index(self.command_palette_selected_index, filtered_length);
    }

    fn append_command_palette_query_char(&mut self, character: char) {
        self.command_palette_query.push(character);
        self.normalize_command_palette_selection();
    }

    fn backspace_command_palette_query(&mut self) {
        self.command_palette_query.pop();
        self.normalize_command_palette_selection();
    }

    fn execute_command_palette_selection(&mut self) -> Option<AppAction> {
        let filtered_indices = self.filtered_command_item_indices();
        let Some(command_palette_item_index) = filtered_indices
            .get(self.command_palette_selected_index)
            .copied()
        else {
            return None;
        };

        let selected_action = COMMAND_PALETTE_ITEMS[command_palette_item_index].action;
        self.close_command_palette();
        Some(selected_action)
    }

    pub fn reduce_action(&mut self, action: AppAction) -> (Option<AppAction>, Option<AppEffect>) {
        match action {
            AppAction::Quit => self.exit = true,
            AppAction::NextPane => self.focus_area = self.focus_area.next(),
            AppAction::PreviousPane => self.focus_area = self.focus_area.previous(),
            AppAction::FocusMeasurementsPane => self.focus_area = FocusArea::Measurements,
            AppAction::FocusNetworkPane => self.focus_area = FocusArea::Network,
            AppAction::FocusFileSystemPane => self.focus_area = FocusArea::FileSystem,
            AppAction::MoveSelectionUp => self.move_selection_previous(),
            AppAction::MoveSelectionDown => self.move_selection_next(),
            AppAction::SelectPreviousMeasurementTab => {
                self.measurement_tab = self.measurement_tab.previous();
            }
            AppAction::SelectNextMeasurementTab => {
                self.measurement_tab = self.measurement_tab.next();
            }
            AppAction::RefreshFileSystem => return (None, Some(AppEffect::RefreshFileSystem)),
            AppAction::ScanNetwork => return (None, Some(AppEffect::ScanNetwork)),
            AppAction::OpenCommandPalette => self.open_command_palette(),
            AppAction::CloseCommandPalette => self.close_command_palette(),
            AppAction::CommandPaletteInputChar(character) => {
                self.append_command_palette_query_char(character)
            }
            AppAction::CommandPaletteBackspace => self.backspace_command_palette_query(),
            AppAction::CommandPaletteSelectUp => self.move_command_palette_selection_previous(),
            AppAction::CommandPaletteSelectDown => self.move_command_palette_selection_next(),
            AppAction::CommandPaletteExecute => {
                return (self.execute_command_palette_selection(), None);
            }
            AppAction::OpenApiBaseUrlEditor => self.open_api_base_url_editor(),
            AppAction::CloseApiBaseUrlEditor => self.close_api_base_url_editor(),
            AppAction::ApiBaseUrlEditorInputChar(character) => {
                self.api_base_url_editor_buffer.push(character)
            }
            AppAction::ApiBaseUrlEditorBackspace => {
                self.api_base_url_editor_buffer.pop();
            }
            AppAction::ApplyApiBaseUrlEditor => self.apply_api_base_url_editor(),
            AppAction::MouseHover { column, row } => {
                if !self.command_palette_open
                    && !self.api_base_url_editor_open
                    && let Some(focus_area) = self.dashboard_areas.focus_area_at(column, row)
                {
                    self.focus_area = focus_area;
                }
            }
            AppAction::Noop => {}
        }

        (None, None)
    }

    fn wrapped_previous_index(current_index: usize, length: usize) -> usize {
        if current_index == 0 {
            length - 1
        } else {
            current_index - 1
        }
    }

    fn wrapped_next_index(current_index: usize, length: usize) -> usize {
        if current_index + 1 >= length {
            0
        } else {
            current_index + 1
        }
    }

    fn move_selection_previous(&mut self) {
        match self.focus_area {
            FocusArea::Measurements => {}
            FocusArea::Network => {
                if self.wireless_networks.is_empty() {
                    self.network_table_state.select(None);
                    return;
                }
                let current_index = self.network_table_state.selected().unwrap_or(0);
                let previous_index =
                    Self::wrapped_previous_index(current_index, self.wireless_networks.len());
                self.network_table_state.select(Some(previous_index));
            }
            FocusArea::FileSystem => {
                #[cfg(not(target_arch = "wasm32"))]
                {
                    self.file_system_tree_state.key_up();
                }

                #[cfg(target_arch = "wasm32")]
                {
                    let total_rows = self.file_system_render_row_count();
                    if total_rows == 0 {
                        self.file_system_list_state.select(None);
                        return;
                    }
                    let current_index = self.file_system_list_state.selected().unwrap_or(0);
                    let previous_index = Self::wrapped_previous_index(current_index, total_rows);
                    self.file_system_list_state.select(Some(previous_index));
                }
            }
        }
    }

    fn move_selection_next(&mut self) {
        match self.focus_area {
            FocusArea::Measurements => {}
            FocusArea::Network => {
                if self.wireless_networks.is_empty() {
                    self.network_table_state.select(None);
                    return;
                }
                let current_index = self.network_table_state.selected().unwrap_or(0);
                let next_index =
                    Self::wrapped_next_index(current_index, self.wireless_networks.len());
                self.network_table_state.select(Some(next_index));
            }
            FocusArea::FileSystem => {
                #[cfg(not(target_arch = "wasm32"))]
                {
                    self.file_system_tree_state.key_down();
                }

                #[cfg(target_arch = "wasm32")]
                {
                    let total_rows = self.file_system_render_row_count();
                    if total_rows == 0 {
                        self.file_system_list_state.select(None);
                        return;
                    }
                    let current_index = self.file_system_list_state.selected().unwrap_or(0);
                    let next_index = Self::wrapped_next_index(current_index, total_rows);
                    self.file_system_list_state.select(Some(next_index));
                }
            }
        }
    }
}
