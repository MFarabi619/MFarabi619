use alloc::{format, string::String, vec, vec::Vec};

use ratatui::{
    Frame,
    layout::{Constraint, Layout, Rect},
    style::{Style, Stylize},
    text::{Line, Span},
    widgets::{Block, Gauge, List, ListItem, Paragraph, Wrap},
};

use crate::{
    app::App,
    panel::{Panel, PanelTag},
    ui::widgets::{kv, panel_title, placeholder_paragraph, render_conf_directives, selection_style, selection_symbol, titled_list_block},
};

pub struct HeapPoolsPanel;

impl Panel for HeapPoolsPanel {
    fn tag(&self) -> PanelTag { PanelTag::HeapPools }
    fn label(&self) -> &'static str { "Heap pools" }
    fn detail_tabs(&self, _app: &App) -> Vec<&'static str> { vec!["Logs", "Stats", "Conf"] }

    fn supports_filter(&self) -> bool { true }

    fn footer_actions(&self, _app: &App) -> alloc::vec::Vec<crate::panel::FooterAction> {
        alloc::vec![("Filter", "/")]
    }

    fn list_len(&self, app: &App) -> usize { matching_indices(app).len() }

    fn current_name(&self, app: &App) -> String {
        selected_entry_index(app)
            .and_then(|i| app.source.heap_pools().get(i))
            .map(|p| p.name.clone()).unwrap_or_default()
    }

    fn render_list(&self, frame: &mut Frame, area: Rect, app: &mut App, focused: bool) {
        let theme    = *app.theme();
        let title    = panel_title(&theme, app.index_of(self.tag()) + 1, self.label(), focused, true);
        let matches  = matching_indices(app);
        let total    = matches.len();
        let selected = app.state_of(self.tag()).list.selected();
        let block    = titled_list_block(&theme, title, focused, selected, total);
        let pools    = app.source.heap_pools();
        let items: Vec<ListItem> = matches.iter().filter_map(|i| pools.get(*i)).map(|pool| {
            let ratio = pool.usage_ratio();
            let color = theme.tier_for_ratio(ratio);
            ListItem::new(Line::from(vec![
                Span::raw(format!("{:<18}", pool.name)).fg(theme.value).bold(),
                Span::raw(format!("{:>3}%", (ratio * 100.0) as u32)).fg(color).bold(),
                Span::raw(format!("  {}/{}", pool.used_blocks(), pool.total_blocks)).fg(theme.label),
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
            "Stats" => self.render_stats_inner(frame, area, app),
            "Conf"  => self.render_conf_inner(frame, area, app),
            _       => self.render_logs_inner(frame, area, app),
        }
    }
}

fn matching_indices(app: &App) -> Vec<usize> {
    let needle = app.state_of(PanelTag::HeapPools).filter.to_lowercase();
    app.source.heap_pools().iter().enumerate()
        .filter(|(_, p)| needle.is_empty() || p.name.to_lowercase().contains(&needle))
        .map(|(i, _)| i).collect()
}

fn selected_entry_index(app: &App) -> Option<usize> {
    let matches = matching_indices(app);
    let pos = app.state_of(PanelTag::HeapPools).list.selected().unwrap_or(0);
    matches.get(pos).copied()
}

impl HeapPoolsPanel {
    fn render_logs_inner(&self, frame: &mut Frame, area: Rect, app: &mut App) {
        let theme = *app.theme();
        let Some(pool) = selected_entry_index(app).and_then(|i| app.source.heap_pools().get(i)) else {
            frame.render_widget(placeholder_paragraph(&theme, "no pool selected"), area);
            return;
        };
        let rows = vec![
            kv(&theme, "name",         pool.name.clone()),
            kv(&theme, "block size",   format!("{} B", pool.block_size)),
            kv(&theme, "total blocks", format!("{}", pool.total_blocks)),
            kv(&theme, "free blocks",  format!("{}", pool.free_blocks)),
            kv(&theme, "used blocks",  format!("{}", pool.used_blocks())),
            kv(&theme, "min free",     format!("{}", pool.min_free)),
        ];
        frame.render_widget(Paragraph::new(rows).wrap(Wrap { trim: false }), area);
    }

    fn render_stats_inner(&self, frame: &mut Frame, area: Rect, app: &mut App) {
        let theme = *app.theme();
        let Some(pool) = selected_entry_index(app).and_then(|i| app.source.heap_pools().get(i)) else {
            frame.render_widget(placeholder_paragraph(&theme, "no heap pool selected"), area);
            return;
        };
        let ratio = pool.usage_ratio();
        let watermark = pool.watermark_ratio();
        let color = theme.tier_for_ratio(ratio);
        let watermark_color = theme.tier_for_ratio(watermark);

        let [_g0, u_label, u_gauge, _g1, w_label, w_gauge, _g2] = Layout::vertical([
            Constraint::Length(1),
            Constraint::Length(1), Constraint::Length(3), Constraint::Length(1),
            Constraint::Length(1), Constraint::Length(3),
            Constraint::Min(0),
        ]).areas(area);

        frame.render_widget(Paragraph::new(Line::from(Span::raw(" current usage ").fg(theme.label))), u_label);
        frame.render_widget(
            Gauge::default()
                .ratio(ratio.min(1.0))
                .gauge_style(Style::new().fg(color).bg(theme.selection_background))
                .label(Span::raw(format!("{}/{} blk · {:.1}%", pool.used_blocks(), pool.total_blocks, ratio * 100.0))
                    .fg(theme.selection_foreground).bold())
                .block(Block::new()),
            u_gauge,
        );
        frame.render_widget(Paragraph::new(Line::from(Span::raw(" peak watermark (min free) ").fg(theme.label))), w_label);
        frame.render_widget(
            Gauge::default()
                .ratio(watermark.min(1.0))
                .gauge_style(Style::new().fg(watermark_color).bg(theme.selection_background))
                .label(Span::raw(format!("min free {} blk · {:.1}% peak", pool.min_free, watermark * 100.0))
                    .fg(theme.selection_foreground).bold())
                .block(Block::new()),
            w_gauge,
        );
    }

    fn render_conf_inner(&self, frame: &mut Frame, area: Rect, app: &mut App) {
        let theme = *app.theme();
        // TODO: parse libs/firmware/**/*.conf instead of hardcoding
        render_conf_directives(frame, area, &theme, &[
            "CONFIG_HEAP_MEM_POOL_SIZE=49152",
            "CONFIG_KERNEL_MEM_POOL=y",
            "CONFIG_NET_BUF_POOL_USAGE=y",
            "CONFIG_MEM_SLAB_TRACE_MAX_UTILIZATION=y",
            "CONFIG_SYS_HEAP_RUNTIME_STATS=y",
        ]);
    }
}
