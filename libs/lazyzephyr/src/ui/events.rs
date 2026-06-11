use alloc::{format, string::String, vec, vec::Vec};

use ratatui::{
    Frame,
    layout::Rect,
    style::Stylize,
    text::{Line, Span},
    widgets::{List, ListItem, Paragraph, Wrap},
};

use crate::{
    app::App,
    panel::{Panel, PanelTag},
    ui::widgets::{highlight_log_line, panel_title, placeholder_paragraph, render_conf_directives, selection_style, selection_symbol, titled_list_block},
};

pub struct EventsPanel;

impl Panel for EventsPanel {
    fn tag(&self) -> PanelTag { PanelTag::Events }
    fn label(&self) -> &'static str { "Events" }
    fn detail_tabs(&self, _app: &App) -> Vec<&'static str> { vec!["Logs", "Conf"] }

    fn footer_actions(&self, _app: &App) -> alloc::vec::Vec<crate::panel::FooterAction> {
        // TODO: wire `c` to clear the events ring buffer.
        alloc::vec![("Clear", "c"), ("Filter", "/")]
    }

    fn supports_filter(&self) -> bool { true }

    fn list_len(&self, app: &App) -> usize {
        matching_indices(app).len()
    }

    fn current_name(&self, app: &App) -> String {
        let matches = matching_indices(app);
        let idx = app.state_of(self.tag()).list.selected().unwrap_or(0);
        matches.get(idx)
            .and_then(|i| app.source.events().get(*i))
            .map(|e| e.timestamp.clone()).unwrap_or_default()
    }

    fn render_list(&self, frame: &mut Frame, area: Rect, app: &mut App, focused: bool) {
        let theme  = *app.theme();
        let title  = panel_title(&theme, app.index_of(self.tag()) + 1, self.label(), focused, false);
        let matches  = matching_indices(app);
        let total    = matches.len();
        let selected = app.state_of(self.tag()).list.selected();
        let block    = titled_list_block(&theme, title, focused, selected, total);

        let visible_indices: &[usize] = if focused { &matches } else { matches.get(..1).unwrap_or(&[]) };
        let events = app.source.events();
        let items: Vec<ListItem> = visible_indices.iter().filter_map(|i| events.get(*i)).map(|event| {
            let level_color = event.level.color(&theme);
            ListItem::new(Line::from(vec![
                Span::raw(format!("{} ", event.timestamp)).fg(level_color).bold(),
                Span::raw(event.message.clone()).fg(theme.foreground),
            ]))
        }).collect();

        let list = List::new(items).block(block)
            .highlight_style(selection_style(&theme, focused))
            .highlight_symbol(selection_symbol(focused));
        let state = &mut app.state_of_mut(self.tag()).list.state;
        frame.render_stateful_widget(list, area, state);
    }

    fn render_detail(&self, frame: &mut Frame, area: Rect, app: &mut App, tab: &str) {
        match tab {
            "Conf" => self.render_conf_inner(frame, area, app),
            _      => self.render_logs_inner(frame, area, app),
        }
    }
}

fn matching_indices(app: &App) -> Vec<usize> {
    let filter = app.state_of(PanelTag::Events).filter.clone();
    let needle = filter.to_lowercase();
    app.source.events().iter().enumerate()
        .filter(|(_, event)| needle.is_empty() || event.message.to_lowercase().contains(&needle))
        .map(|(i, _)| i)
        .collect()
}

impl EventsPanel {
    fn render_logs_inner(&self, frame: &mut Frame, area: Rect, app: &mut App) {
        let theme = *app.theme();
        let matches = matching_indices(app);
        let idx = app.state_of(self.tag()).list.selected().unwrap_or(0);
        let Some(event) = matches.get(idx).and_then(|i| app.source.events().get(*i)) else {
            frame.render_widget(placeholder_paragraph(&theme, "no event selected"), area);
            return;
        };
        let lines: Vec<Line<'static>> = vec![
            Line::from(vec![
                Span::raw(format!("{} ", event.level.icon())).fg(event.level.color(&theme)).bold(),
                Span::raw(format!("{}  ", event.timestamp)).fg(theme.label),
                Span::raw(format!("{:?}", event.level)).fg(event.level.color(&theme)).bold(),
            ]),
            Line::from(""),
            highlight_log_line(&theme, &event.message),
        ];
        frame.render_widget(Paragraph::new(lines).wrap(Wrap { trim: false }), area);
    }

    fn render_conf_inner(&self, frame: &mut Frame, area: Rect, app: &mut App) {
        let theme = *app.theme();
        // TODO: parse libs/firmware/**/*.conf instead of hardcoding
        render_conf_directives(frame, area, &theme, &[
            "CONFIG_LOG=y",
            "CONFIG_LOG_MODE_DEFERRED=y",
            "CONFIG_LOG_PROCESS_THREAD=y",
            "CONFIG_LOG_BUFFER_SIZE=4096",
            "CONFIG_LOG_DEFAULT_LEVEL=3",
            "CONFIG_LOG_BACKEND_UART=y",
        ]);
    }
}
