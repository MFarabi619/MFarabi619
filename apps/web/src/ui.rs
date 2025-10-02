use ratatui::widgets::BorderType;
use ratzilla::ratatui::{
    layout::{Alignment, Constraint, Layout, Rect},
    style::{Color, Modifier, Style},
    symbols,
    text::{self, Span},
    widgets::{
        canvas::{self, Canvas, Circle, Map, MapResolution, Rectangle},
        Block, Cell, Paragraph, Row, Table, Tabs, Wrap,
    },
    Frame,
};
use tachyonfx::Duration;
// use tui_big_text::{BigText, PixelSize};

use crate::app::App;

pub fn draw(elapsed: Duration, frame: &mut Frame, app: &mut App) {
    let chunks = Layout::vertical([Constraint::Length(3), Constraint::Min(0)]).split(frame.area());
    let tabs = app
        .tabs
        .titles
        .iter()
        .map(|t| text::Line::from(Span::styled(*t, Style::default().fg(Color::LightGreen))))
        .collect::<Tabs>()
        .block(
            Block::bordered()
                .title(Span::styled(
                    app.title,
                    Style::default()
                        .fg(Color::LightMagenta)
                        .add_modifier(Modifier::BOLD),
                ))
                .title_alignment(Alignment::Center)
                .border_style(Color::Magenta)
                .border_type(BorderType::Double),
        )
        .highlight_style(Style::default().fg(Color::LightYellow))
        .select(app.tabs.index);
    frame.render_widget(tabs, chunks[0]);
    match app.tabs.index {
        0 => draw_first_tab(frame, app, chunks[1]),
        1 => draw_second_tab(frame, app, chunks[1]),
        2 => draw_third_tab(frame, app, chunks[1]),
        _ => {}
    };

    let area = frame.area();
    app.effects
        .process_effects(elapsed, frame.buffer_mut(), area);
}

fn draw_first_tab(frame: &mut Frame, _app: &mut App, area: Rect) {
    draw_text(frame, area);
}

fn draw_text(frame: &mut Frame, area: Rect) {
    use ratzilla::ratatui::text::Line;

    let text = vec![
        Line::from(""),
        Line::from(vec![Span::styled(
            " ⚓ Open-Source @ Microvisor Systems & LikeC4 core team 🧊",
            Style::default()
                .fg(Color::LightCyan)
                .add_modifier(Modifier::BOLD),
        )]),
        Line::from(""),
        Line::from(Span::styled(
            "🏗  Site under construction 🏗",
            Style::default().fg(Color::LightYellow),
        )),
        Line::from(""),
        Line::from(Span::styled(
            "🎨 ========== ~/artwork ========== 🎨",
            Style::default()
                .fg(Color::LightMagenta)
                .add_modifier(Modifier::BOLD),
        )),
        Line::from(""),
        Line::from("👹 DoomBSD:                 🏗"),
        Line::from("🧮 Microvisor:              🏗"),
        Line::from("🦕 Mira AMM:                mira.ly"),
        Line::from("⌨  cuHacking 2025 Platform: docs.cuhacking.ca"),
        Line::from(""),
        Line::from(Span::styled(
            "📱 ========== ~/socials ========== 📱",
            Style::default()
                .fg(Color::LightMagenta)
                .add_modifier(Modifier::BOLD),
        )),
        Line::from(""),
        Line::from("🥂 LinkedIn:                linkedin.com/in/mfarabi"),
        Line::from("🐙 GitHub:                  github.com/MFarabi619/MFarabi619"),
        Line::from(""),
        Line::from(Span::styled(
            "🤔 =========== ~/todo ============ 🤔",
            Style::default()
                .fg(Color::LightMagenta)
                .add_modifier(Modifier::BOLD),
        )),
        Line::from(""),
        Line::from(" [DONE] Create something, anything"),
        Line::from(" [DONE] Deploy to Netlify"),
        Line::from(" [DONE] Make responsive"),
        Line::from(" [ ] Self-host from home data center with Kubernetes and/or Kubenix"),
        Line::from(" [ ] Add hyperlink support"),
        Line::from(" [ ] Add markdown support"),
        Line::from(" [ ] Set up CI"),
        Line::from(" [ ] Create regression test suite"),
        Line::from(" [ ] Teach others how to do it too"),
        Line::from(""),
        Line::from(Span::styled(
            "🐞 github.com/MFarabi619/MFarabi619/apps/web",
            Style::default()
                .fg(Color::LightCyan)
                .add_modifier(Modifier::UNDERLINED),
        )),
        Line::from(""),
        Line::from(vec![
            Span::raw("Made with utmost ❤️‍🔥 by 🙌 using "),
            Span::styled("🦀 Rust", Style::default().fg(Color::Rgb(250, 100, 0))),
            Span::raw(", "),
            Span::styled("❄ Nix", Style::default().fg(Color::Rgb(80, 130, 255))),
            Span::raw(", "),
            Span::styled("👹 FreeBSD", Style::default().fg(Color::LightRed)),
            Span::raw(", and "),
            Span::styled("🐏 GNU/Linux 🐧", Style::default().fg(Color::LightGreen)),
            Span::raw("."),
        ]),
        Line::from(""),
        Line::from(vec![
            Span::raw("Site theme heavily inspired by "),
            Span::styled("Xe Iaso's ", Style::default().fg(Color::LightMagenta)),
            Span::raw("blog: "),
            Span::styled("xeiaso.net", Style::default().fg(Color::LightCyan)),
        ]),
    ];

    let block = Block::bordered()
        .border_style(Color::Magenta)
        .border_type(BorderType::Double)
        .title(Span::styled(
            "📚 README 📚",
            Style::default()
                .fg(Color::LightMagenta)
                .add_modifier(Modifier::BOLD),
        ));

    let paragraph = Paragraph::new(text).block(block).wrap(Wrap { trim: true });
    frame.render_widget(paragraph, area);
}

fn draw_second_tab(frame: &mut Frame, app: &mut App, area: Rect) {
    let chunks =
        Layout::horizontal([Constraint::Percentage(100), Constraint::Percentage(00)]).split(area);
    let up_style = Style::default().fg(Color::LightGreen);
    let idle_style = Style::default().fg(Color::LightYellow);
    let failure_style = Style::default()
        .fg(Color::LightRed)
        .add_modifier(Modifier::RAPID_BLINK | Modifier::CROSSED_OUT);
    let rows = app.servers.iter().map(|s| {
        let style = if s.status == "Up" {
            up_style
        } else if s.status == "Idle" {
            idle_style
        } else {
            failure_style
        };
        Row::new(vec![
            s.user, s.hostname, s.chassis, s.os, s.kernel, s.display, s.desktop, s.cpu, s.gpu,
            s.memory, s.disk, s.uptime, s.terminal, s.location, s.status,
        ])
        .style(style)
    });
    let table = Table::new(
        rows,
        [
            Constraint::Length(10),
            Constraint::Length(18),
            Constraint::Length(18),
            Constraint::Length(18),
            Constraint::Length(18),
            Constraint::Length(18),
            Constraint::Length(18),
            Constraint::Length(18),
            Constraint::Length(15),
            Constraint::Length(15),
            Constraint::Length(10),
            Constraint::Length(10),
            Constraint::Length(10),
            Constraint::Length(10),
            Constraint::Length(10),
            Constraint::Length(10),
            Constraint::Length(10),
        ],
    )
    .header(
        Row::new(vec![
            "👿 User",
            "🏷 Hostname",
            "🏎 Chassis",
            "🐧 OS",
            "🖥 Kernel",
            "🏎 Display",
            "🍚 DE/WM",
            "🧠 CPU",
            "🧫 GPU",
            "💽 Memory",
            "💾 Disk",
            "🧫 Uptime",
            "🕹 Terminal",
            "🌍 Location",
            "🔍 Status",
        ])
        .style(Style::default().fg(Color::White))
        .top_margin(1)
        .bottom_margin(1),
    )
    .block(
        Block::bordered()
            .title(Span::styled(
                "📠 Servers 📠",
                Style::default()
                    .fg(Color::LightMagenta)
                    .add_modifier(Modifier::BOLD),
            ))
            .border_style(Color::Magenta)
            .border_type(BorderType::Double),
    );
    frame.render_widget(table, chunks[0]);

    let map = Canvas::default()
        .block(Block::bordered().title("World"))
        .paint(|ctx| {
            ctx.draw(&Map {
                color: Color::White,
                resolution: MapResolution::High,
            });
            ctx.layer();
            ctx.draw(&Rectangle {
                x: 0.0,
                y: 30.0,
                width: 10.0,
                height: 10.0,
                color: Color::Yellow,
            });
            ctx.draw(&Circle {
                x: app.servers[2].coords.1,
                y: app.servers[2].coords.0,
                radius: 10.0,
                color: Color::LightGreen,
            });
            for (i, s1) in app.servers.iter().enumerate() {
                for s2 in &app.servers[i + 1..] {
                    ctx.draw(&canvas::Line {
                        x1: s1.coords.1,
                        y1: s1.coords.0,
                        y2: s2.coords.0,
                        x2: s2.coords.1,
                        color: Color::Yellow,
                    });
                }
            }
            for server in &app.servers {
                let color = if server.status == "Up" {
                    Color::LightGreen
                } else {
                    Color::LightYellow
                };
                ctx.print(
                    server.coords.1,
                    server.coords.0,
                    Span::styled("X", Style::default().fg(color)),
                );
            }
        })
        .marker(if app.enhanced_graphics {
            symbols::Marker::Braille
        } else {
            symbols::Marker::Dot
        })
        .x_bounds([-180.0, 180.0])
        .y_bounds([-90.0, 90.0]);
    // frame.render_widget(map, chunks[1]);
}

fn draw_third_tab(frame: &mut Frame, _app: &mut App, area: Rect) {
    // let chunks = Layout::horizontal([Constraint::Ratio(1, 2), Constraint::Ratio(1, 2)]).split(area);
    let chunks = Layout::horizontal([Constraint::Ratio(1, 1)]).split(area);
    let colors = [
        Color::Reset,
        Color::Black,
        Color::Red,
        Color::Green,
        Color::Yellow,
        Color::Blue,
        Color::LightMagenta,
        Color::Cyan,
        Color::Gray,
        Color::DarkGray,
        Color::LightRed,
        Color::LightGreen,
        Color::LightYellow,
        Color::LightBlue,
        Color::LightMagenta,
        Color::LightCyan,
        Color::White,
    ];
    let items: Vec<Row> = colors
        .iter()
        .map(|c| {
            let cells = vec![
                Cell::from(Span::raw(format!("{c:?}: "))),
                Cell::from(Span::styled("Foreground", Style::default().fg(*c))),
                Cell::from(Span::styled("Background", Style::default().bg(*c))),
            ];
            Row::new(cells)
        })
        .collect();

    let table = Table::new(
        items,
        [
            Constraint::Ratio(1, 3),
            Constraint::Ratio(1, 3),
            Constraint::Ratio(1, 3),
            Constraint::Ratio(1, 3),
            Constraint::Ratio(1, 3),
        ],
    )
    .block(
        Block::bordered()
            .title(Span::styled(
                "🤹 workspace 🤹",
                Style::default()
                    .fg(Color::LightMagenta)
                    .add_modifier(Modifier::BOLD),
            ))
            .border_style(Color::Magenta)
            .border_type(BorderType::Double),
    );

    frame.render_widget(table, chunks[0]);
}
