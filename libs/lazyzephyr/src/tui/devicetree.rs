use alloc::{format, vec::Vec};

use ratatui::{
    Frame,
    layout::{Constraint, Layout, Rect},
    style::{Color, Style, Stylize, palette::tailwind},
    text::{Line, Span},
    widgets::{Block, BorderType, Paragraph},
};

use crate::tui::state::App;

#[derive(Clone, Copy)]
enum PinKind {
    System,
    Power,
    Gnd,
    Digital,
    Adc,
    PinName,
    Spi,
    Uart,
    Iic,
    Peripheral,
}

struct PinChip {
    label: &'static str,
    kind:  PinKind,
}

struct PinRow {
    marker: PinChip,
    chips:  &'static [PinChip],
}

type Slot = Option<PinChip>;

const LEFT_ROWS: &[PinRow] = &[
    PinRow { marker: PinChip{label:"1",  kind:PinKind::PinName}, chips: &[
        PinChip{label:"RTC",      kind:PinKind::System},
        PinChip{label:"ADC1/A0",  kind:PinKind::Adc},
        PinChip{label:"D0/T",     kind:PinKind::Digital},
    ]},
    PinRow { marker: PinChip{label:"2",  kind:PinKind::PinName}, chips: &[
        PinChip{label:"RTC",      kind:PinKind::System},
        PinChip{label:"ADC1/A1",  kind:PinKind::Adc},
        PinChip{label:"D1/T",     kind:PinKind::Digital},
    ]},
    PinRow { marker: PinChip{label:"3",  kind:PinKind::PinName}, chips: &[
        PinChip{label:"RTC",      kind:PinKind::System},
        PinChip{label:"ADC1/A2",  kind:PinKind::Adc},
        PinChip{label:"D2/T",     kind:PinKind::Digital},
    ]},
    PinRow { marker: PinChip{label:"4",  kind:PinKind::PinName}, chips: &[
        PinChip{label:"RTC",      kind:PinKind::System},
        PinChip{label:"ADC1/A3",  kind:PinKind::Adc},
        PinChip{label:"D3/T",     kind:PinKind::Digital},
    ]},
    PinRow { marker: PinChip{label:"5",  kind:PinKind::PinName}, chips: &[
        PinChip{label:"RTC",      kind:PinKind::System},
        PinChip{label:"I2C1_SDA", kind:PinKind::Iic},
        PinChip{label:"ADC1/A4",  kind:PinKind::Adc},
        PinChip{label:"D4/T",     kind:PinKind::Digital},
    ]},
    PinRow { marker: PinChip{label:"6",  kind:PinKind::PinName}, chips: &[
        PinChip{label:"RTC",      kind:PinKind::System},
        PinChip{label:"I2C1_SCL", kind:PinKind::Iic},
        PinChip{label:"ADC1/A5",  kind:PinKind::Adc},
        PinChip{label:"D5/T",     kind:PinKind::Digital},
    ]},
    PinRow { marker: PinChip{label:"43", kind:PinKind::PinName}, chips: &[
        PinChip{label:"UART0_TX", kind:PinKind::Uart},
        PinChip{label:"D6",       kind:PinKind::Digital},
    ]},
    PinRow { marker: PinChip{label:"LNA", kind:PinKind::PinName}, chips: &[
        PinChip{label:"Ext. Antenna", kind:PinKind::Peripheral},
    ]},
];

const RIGHT_ROWS: &[PinRow] = &[
    PinRow { marker: PinChip{label:"VBUS",    kind:PinKind::Power}, chips: &[] },
    PinRow { marker: PinChip{label:"GND",     kind:PinKind::Gnd},   chips: &[] },
    PinRow { marker: PinChip{label:"3V3-OUT", kind:PinKind::Power}, chips: &[] },
    PinRow { marker: PinChip{label:"9",  kind:PinKind::PinName}, chips: &[
        PinChip{label:"D10/T",     kind:PinKind::Digital},
        PinChip{label:"ADC1/A10",  kind:PinKind::Adc},
        PinChip{label:"SPI0_MOSI", kind:PinKind::Spi},
        PinChip{label:"RTC",       kind:PinKind::System},
    ]},
    PinRow { marker: PinChip{label:"8",  kind:PinKind::PinName}, chips: &[
        PinChip{label:"D9/T",      kind:PinKind::Digital},
        PinChip{label:"ADC1/A9",   kind:PinKind::Adc},
        PinChip{label:"SPI0_MISO", kind:PinKind::Spi},
        PinChip{label:"RTC",       kind:PinKind::System},
    ]},
    PinRow { marker: PinChip{label:"7",  kind:PinKind::PinName}, chips: &[
        PinChip{label:"D8/T",     kind:PinKind::Digital},
        PinChip{label:"ADC1/A8",  kind:PinKind::Adc},
        PinChip{label:"SPI0_SCK", kind:PinKind::Spi},
        PinChip{label:"RTC",      kind:PinKind::System},
    ]},
    PinRow { marker: PinChip{label:"44", kind:PinKind::PinName}, chips: &[
        PinChip{label:"D7",       kind:PinKind::Digital},
        PinChip{label:"UART0_RX", kind:PinKind::Uart},
    ]},
];

const TOP_LEFT_ROWS: &[&[Slot]] = &[
    &[Some(PinChip{label:"RESET",      kind:PinKind::System}), Some(PinChip{label:"CHIP_PU", kind:PinKind::Peripheral})],
    &[Some(PinChip{label:"CHARGE_LED", kind:PinKind::System}), None],
];

const TOP_RIGHT_ROWS: &[&[Slot]] = &[
    &[Some(PinChip{label:"GPIO0",  kind:PinKind::PinName}), Some(PinChip{label:"BOOT",     kind:PinKind::System})],
    &[Some(PinChip{label:"GPIO21", kind:PinKind::PinName}), Some(PinChip{label:"USER_LED", kind:PinKind::Peripheral})],
];

fn palette(kind: PinKind) -> (Color, Color) {
    match kind {
        PinKind::System     => (tailwind::SLATE.c500,   Color::White),
        PinKind::Power      => (tailwind::RED.c600,     Color::White),
        PinKind::Gnd        => (tailwind::NEUTRAL.c900, Color::White),
        PinKind::Digital    => (tailwind::LIME.c500,    Color::Black),
        PinKind::Adc        => (tailwind::ORANGE.c500,  Color::Black),
        PinKind::PinName    => (tailwind::AMBER.c700,   Color::White),
        PinKind::Spi        => (tailwind::VIOLET.c500,  Color::White),
        PinKind::Uart       => (tailwind::ROSE.c500,    Color::White),
        PinKind::Iic        => (tailwind::CYAN.c600,    Color::White),
        PinKind::Peripheral => (tailwind::STONE.c500,   Color::White),
    }
}

fn chip_span(c: &PinChip) -> Span<'static> {
    let (bg, fg) = palette(c.kind);
    let padded = format!(" {} ", c.label);
    Span::styled(padded, Style::new().bg(bg).fg(fg).bold())
}

fn left_row_line(row: &PinRow) -> Line<'static> {
    let mut spans: Vec<Span<'static>> = Vec::new();
    for chip in row.chips {
        spans.push(chip_span(chip));
        spans.push(" ".into());
    }
    spans.push(chip_span(&row.marker));
    Line::from(spans).right_aligned()
}

fn right_row_line(row: &PinRow) -> Line<'static> {
    let mut spans: Vec<Span<'static>> = Vec::new();
    spans.push(chip_span(&row.marker));
    for chip in row.chips {
        spans.push(" ".into());
        spans.push(chip_span(chip));
    }
    Line::from(spans)
}

fn top_line(row: &[Slot], align_right: bool) -> Line<'static> {
    let mut spans: Vec<Span<'static>> = Vec::new();
    for (i, slot) in row.iter().enumerate() {
        if let Some(c) = slot {
            spans.push(chip_span(c));
            if i + 1 < row.len() { spans.push(" ".into()); }
        }
    }
    let line = Line::from(spans);
    if align_right { line.right_aligned() } else { line }
}

pub fn render(frame: &mut Frame, area: Rect, _app: &App) {
    let body_width:  u16 = 36;
    let body_height: u16 = 14;

    let [top_area, main_area, legend_area] = Layout::vertical([
        Constraint::Length(5),
        Constraint::Fill(1),
        Constraint::Length(3),
    ]).areas(area);

    let [left_area, mid_area, right_area] = Layout::horizontal([
        Constraint::Fill(1),
        Constraint::Length(body_width),
        Constraint::Fill(1),
    ]).areas(main_area);

    let [_top_pad, body_area, _bot_pad] = Layout::vertical([
        Constraint::Fill(1),
        Constraint::Length(body_height),
        Constraint::Fill(1),
    ]).areas(mid_area);

    let [top_left, _top_mid, top_right] = Layout::horizontal([
        Constraint::Fill(1),
        Constraint::Length(body_width),
        Constraint::Fill(1),
    ]).areas(top_area);

    render_top(frame, top_left, TOP_LEFT_ROWS, true);
    render_top(frame, top_right, TOP_RIGHT_ROWS, false);
    render_left(frame, left_area);
    render_body(frame, body_area);
    render_right(frame, right_area);
    render_legend(frame, legend_area);
}

fn interleave_with_gaps(lines: Vec<Line<'static>>) -> Vec<Line<'static>> {
    let mut out: Vec<Line<'static>> = Vec::with_capacity(lines.len().saturating_mul(2).saturating_sub(1));
    for (i, l) in lines.into_iter().enumerate() {
        if i > 0 { out.push(Line::from("")); }
        out.push(l);
    }
    out
}

fn render_top(frame: &mut Frame, area: Rect, rows: &[&[Slot]], align_right: bool) {
    let raw: Vec<Line<'static>> = rows.iter().map(|r| top_line(r, align_right)).collect();
    let lines = interleave_with_gaps(raw);
    frame.render_widget(Paragraph::new(lines), area);
}

fn render_left(frame: &mut Frame, area: Rect) {
    let raw: Vec<Line<'static>> = LEFT_ROWS.iter().map(left_row_line).collect();
    let lines = interleave_with_gaps(raw);
    let n_lines = lines.len() as u16;
    if area.height < n_lines { return; }
    let pad = (area.height.saturating_sub(n_lines)) / 2;
    let inner = Rect { x: area.x, y: area.y + pad, width: area.width, height: n_lines };
    frame.render_widget(Paragraph::new(lines), inner);
}

fn render_right(frame: &mut Frame, area: Rect) {
    let raw: Vec<Line<'static>> = RIGHT_ROWS.iter().map(right_row_line).collect();
    let lines = interleave_with_gaps(raw);
    let n_lines = lines.len() as u16;
    if area.height < n_lines { return; }
    let pad = (area.height.saturating_sub(n_lines)) / 2;
    let inner = Rect { x: area.x, y: area.y + pad, width: area.width, height: n_lines };
    frame.render_widget(Paragraph::new(lines), inner);
}

fn render_body(frame: &mut Frame, area: Rect) {
    let block = Block::bordered()
        .border_type(BorderType::Rounded)
        .border_style(Style::new().fg(tailwind::ZINC.c500));
    let inner = block.inner(area);
    frame.render_widget(block, area);
    if inner.height < 6 { return; }

    let buttons = Line::from(alloc::vec![
        "R".fg(tailwind::RED.c400).bold(),
        "    USB-C    ".fg(tailwind::ZINC.c300),
        "B".fg(tailwind::SKY.c400).bold(),
    ]).centered();
    let pads = "▆▆▆▆▆▆▆▆▆▆▆▆▆▆".fg(tailwind::AMBER.c500);

    let lines: Vec<Line<'static>> = alloc::vec![
        Line::from("").centered(),
        buttons,
        Line::from("").centered(),
        Line::from("seeed studio".fg(Color::White).bold()).centered(),
        Line::from("Model: XIAO-ESP32-S3".fg(tailwind::ZINC.c200)).centered(),
        Line::from("FCC ID: Z4T-XIAOESP32S3".fg(tailwind::ZINC.c400)).centered(),
        Line::from("").centered(),
        Line::from(pads).centered(),
    ];

    let total_lines = lines.len() as u16;
    let pad_top: u16 = inner.height.saturating_sub(total_lines) / 2;
    let body_inner = Rect {
        x: inner.x,
        y: inner.y + pad_top,
        width: inner.width,
        height: total_lines.min(inner.height),
    };
    frame.render_widget(Paragraph::new(lines), body_inner);
}

fn render_legend(frame: &mut Frame, area: Rect) {
    let entries = [
        ("SYSTEM",       PinKind::System),
        ("POWER",        PinKind::Power),
        ("GND",          PinKind::Gnd),
        ("DIGITAL GPIO", PinKind::Digital),
        ("ADC INPUT",    PinKind::Adc),
        ("PIN NAME",     PinKind::PinName),
        ("SPI",          PinKind::Spi),
        ("UART",         PinKind::Uart),
        ("I2C",          PinKind::Iic),
        ("PERIPHERAL",   PinKind::Peripheral),
    ];
    let mut spans: Vec<Span<'static>> = Vec::new();
    for (i, (label, kind)) in entries.iter().enumerate() {
        if i > 0 { spans.push("  ".into()); }
        let (bg, fg) = palette(*kind);
        spans.push(Span::styled(format!(" {label} "), Style::new().bg(bg).fg(fg).bold()));
    }
    let line = Line::from(spans).centered();
    let block = Block::bordered()
        .border_type(BorderType::Rounded)
        .border_style(Style::new().fg(tailwind::ZINC.c700))
        .title(" Legend ".fg(tailwind::ZINC.c400).bold());
    let inner = block.inner(area);
    frame.render_widget(block, area);
    frame.render_widget(Paragraph::new(line), inner);
}
