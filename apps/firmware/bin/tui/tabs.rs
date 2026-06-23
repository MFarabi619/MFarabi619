use std::vec::Vec;

use ratatui::{
    Frame,
    buffer::Buffer,
    layout::{Constraint, Layout, Rect},
    style::{Color, Style},
    symbols,
    text::Line,
    widgets::{
        Bar, BarChart, BarGroup, Block, Padding, Paragraph, Tabs, Widget, Wrap,
        calendar::{CalendarEventStore, Monthly},
    },
};
use time::{Date, Month};

const LOREM_IPSUM: &str = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.";

pub struct TabsState {
    pub selected_tab: usize,
    temperatures: [u8; 6],
}

impl TabsState {
    pub fn new() -> Self {
        Self {
            selected_tab: 0,
            temperatures: [62, 65, 72, 78, 75, 68],
        }
    }

    pub fn next(&mut self) {
        self.selected_tab = (self.selected_tab + 1) % 3;
    }
}

impl Default for TabsState {
    fn default() -> Self {
        Self::new()
    }
}

pub fn draw_tabs(frame: &mut Frame, state: &TabsState) {
    let area = frame.area();
    let [header_area, inner_area, footer_area] = Layout::vertical([
        Constraint::Length(1),
        Constraint::Min(0),
        Constraint::Length(1),
    ])
    .areas(area);

    render_header(state, header_area, frame.buffer_mut());

    let block = Block::bordered()
        .border_set(symbols::border::PROPORTIONAL_TALL)
        .padding(Padding::horizontal(1))
        .border_style(Style::new().fg(Color::Yellow));

    match state.selected_tab {
        0 => {
            Paragraph::new(LOREM_IPSUM)
                .wrap(Wrap { trim: true })
                .block(block)
                .render(inner_area, frame.buffer_mut());
        }
        1 => {
            let default_style = Style::default()
                .bg(Color::Rgb(50, 50, 50))
                .fg(Color::Yellow);
            let events = CalendarEventStore::default();
            Monthly::new(
                Date::from_calendar_date(2025, Month::May, 23).unwrap(),
                events,
            )
            .show_month_header(Style::default().fg(Color::Yellow))
            .default_style(default_style)
            .block(block)
            .render(inner_area, frame.buffer_mut());
        }
        2 => {
            vertical_barchart(&state.temperatures)
                .block(block)
                .render(inner_area, frame.buffer_mut());
        }
        _ => {}
    }

    render_footer(footer_area, frame.buffer_mut());
}

fn render_header(state: &TabsState, area: Rect, buf: &mut Buffer) {
    let titles = ["[Paragraph]", "[Calendar]", "[Barchart]"];
    Tabs::new(titles)
        .style(Style::new().bg(Color::Black).fg(Color::Yellow))
        .highlight_style(Style::new().bg(Color::Yellow).fg(Color::Black))
        .select(state.selected_tab)
        .render(area, buf);
}

fn render_footer(area: Rect, buf: &mut Buffer) {
    Line::raw("[Tab] cycle  [q] quit")
        .centered()
        .style(Style::default().fg(Color::Gray))
        .render(area, buf);
}

fn vertical_barchart(temperatures: &[u8]) -> BarChart<'_> {
    let bars: Vec<Bar> = temperatures
        .iter()
        .enumerate()
        .map(|(hour, value)| vertical_bar(hour, value))
        .collect();
    let title = Line::from("Weather (Vertical)").centered();
    BarChart::default()
        .data(BarGroup::default().bars(&bars))
        .block(Block::new().title(title))
        .bar_width(5)
}

fn vertical_bar(hour: usize, temperature: &u8) -> Bar<'_> {
    Bar::default()
        .value(u64::from(*temperature))
        .label(Line::from(format!("{hour:>02}:00")))
        .text_value(format!("{temperature:>3}\u{00b0}"))
        .style(temperature_style(*temperature))
        .value_style(label_style(*temperature))
}

fn temperature_style(value: u8) -> Style {
    let green = (255.0 * (1.0 - f64::from(value - 50) / 40.0)) as u8;
    Style::new().fg(Color::Rgb(255, green, 0))
}

fn label_style(value: u8) -> Style {
    let green = (255.0 * (1.0 - f64::from(value - 50) / 40.0)) as u8;
    Style::new().bg(Color::Rgb(255, green, 0)).fg(Color::Black)
}
