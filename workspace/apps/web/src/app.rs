use crate::effects;
use rand::{
    distributions::{Distribution, Uniform},
    rngs::SmallRng,
    SeedableRng,
};
use ratzilla::ratatui::widgets::ListState;
use tachyonfx::{Duration, EffectManager};

const TASKS: [&str; 24] = [
    "Item1", "Item2", "Item3", "Item4", "Item5", "Item6", "Item7", "Item8", "Item9", "Item10",
    "Item11", "Item12", "Item13", "Item14", "Item15", "Item16", "Item17", "Item18", "Item19",
    "Item20", "Item21", "Item22", "Item23", "Item24",
];

const LOGS: [(&str, &str); 26] = [
    ("Event1", "INFO"),
    ("Event2", "INFO"),
    ("Event3", "CRITICAL"),
    ("Event4", "ERROR"),
    ("Event5", "INFO"),
    ("Event6", "INFO"),
    ("Event7", "WARNING"),
    ("Event8", "INFO"),
    ("Event9", "INFO"),
    ("Event10", "INFO"),
    ("Event11", "CRITICAL"),
    ("Event12", "INFO"),
    ("Event13", "INFO"),
    ("Event14", "INFO"),
    ("Event15", "INFO"),
    ("Event16", "INFO"),
    ("Event17", "ERROR"),
    ("Event18", "ERROR"),
    ("Event19", "INFO"),
    ("Event20", "INFO"),
    ("Event21", "WARNING"),
    ("Event22", "INFO"),
    ("Event23", "INFO"),
    ("Event24", "WARNING"),
    ("Event25", "INFO"),
    ("Event26", "INFO"),
];

const EVENTS: [(&str, u64); 24] = [
    ("B1", 9),
    ("B2", 12),
    ("B3", 5),
    ("B4", 8),
    ("B5", 2),
    ("B6", 4),
    ("B7", 5),
    ("B8", 9),
    ("B9", 14),
    ("B10", 15),
    ("B11", 1),
    ("B12", 0),
    ("B13", 4),
    ("B14", 6),
    ("B15", 4),
    ("B16", 6),
    ("B17", 4),
    ("B18", 7),
    ("B19", 13),
    ("B20", 8),
    ("B21", 11),
    ("B22", 9),
    ("B23", 3),
    ("B24", 5),
];

#[derive(Clone)]
pub struct RandomSignal {
    distribution: Uniform<u64>,
    rng: SmallRng,
}

impl RandomSignal {
    pub fn new(lower: u64, upper: u64) -> Self {
        Self {
            distribution: Uniform::new(lower, upper),
            rng: SmallRng::seed_from_u64(0),
        }
    }
}

impl Iterator for RandomSignal {
    type Item = u64;
    fn next(&mut self) -> Option<u64> {
        Some(self.distribution.sample(&mut self.rng))
    }
}

#[derive(Clone)]
pub struct SinSignal {
    x: f64,
    interval: f64,
    period: f64,
    scale: f64,
}

impl SinSignal {
    pub const fn new(interval: f64, period: f64, scale: f64) -> Self {
        Self {
            x: 0.0,
            interval,
            period,
            scale,
        }
    }
}

impl Iterator for SinSignal {
    type Item = (f64, f64);
    fn next(&mut self) -> Option<Self::Item> {
        let point = (self.x, (self.x * 1.0 / self.period).sin() * self.scale);
        self.x += self.interval;
        Some(point)
    }
}

pub struct TabsState<'a> {
    pub titles: Vec<&'a str>,
    pub index: usize,
}

impl<'a> TabsState<'a> {
    pub const fn new(titles: Vec<&'a str>) -> Self {
        Self { titles, index: 0 }
    }
    pub fn next(&mut self) {
        self.index = (self.index + 1) % self.titles.len();
    }

    pub fn previous(&mut self) {
        if self.index > 0 {
            self.index -= 1;
        } else {
            self.index = self.titles.len() - 1;
        }
    }
}

pub struct StatefulList<T> {
    pub state: ListState,
    pub items: Vec<T>,
}

impl<T> StatefulList<T> {
    pub fn with_items(items: Vec<T>) -> Self {
        Self {
            state: ListState::default(),
            items,
        }
    }

    pub fn next(&mut self) {
        let i = match self.state.selected() {
            Some(i) => {
                if i >= self.items.len() - 1 {
                    0
                } else {
                    i + 1
                }
            }
            None => 0,
        };
        self.state.select(Some(i));
    }

    pub fn previous(&mut self) {
        let i = match self.state.selected() {
            Some(i) => {
                if i == 0 {
                    self.items.len() - 1
                } else {
                    i - 1
                }
            }
            None => 0,
        };
        self.state.select(Some(i));
    }
}

pub struct Signal<S: Iterator> {
    source: S,
    pub points: Vec<S::Item>,
    tick_rate: usize,
}

impl<S> Signal<S>
where
    S: Iterator,
{
    fn on_tick(&mut self) {
        self.points.drain(0..self.tick_rate);
        self.points
            .extend(self.source.by_ref().take(self.tick_rate));
    }
}

pub struct Signals {
    pub sin1: Signal<SinSignal>,
    pub sin2: Signal<SinSignal>,
    pub window: [f64; 2],
}

impl Signals {
    fn on_tick(&mut self) {
        self.sin1.on_tick();
        self.sin2.on_tick();
        self.window[0] += 1.0;
        self.window[1] += 1.0;
    }
}

pub struct Server<'a> {
    pub user: &'a str,
    pub hostname: &'a str,
    pub chassis: &'a str,
    pub os: &'a str,
    pub kernel: &'a str,
    pub display: &'a str,
    pub desktop: &'a str,
    pub cpu: &'a str,
    pub gpu: &'a str,
    pub memory: &'a str,
    pub disk: &'a str,
    pub uptime: &'a str,
    pub terminal: &'a str,
    pub location: &'a str,
    pub coords: (f64, f64),
    pub status: &'a str,
}

pub struct App<'a> {
    pub title: &'a str,
    pub should_quit: bool,
    pub tabs: TabsState<'a>,
    pub show_chart: bool,
    pub progress: f64,
    pub sparkline: Signal<RandomSignal>,
    pub tasks: StatefulList<&'a str>,
    pub logs: StatefulList<(&'a str, &'a str)>,
    pub signals: Signals,
    pub barchart: Vec<(&'a str, u64)>,
    pub servers: Vec<Server<'a>>,
    pub enhanced_graphics: bool,
    pub effects: EffectManager<EffectKey>,
    pub last_frame: web_time::Instant,
}

#[derive(Clone, Copy, Debug, Default, Ord, PartialOrd, Eq, PartialEq)]
pub enum EffectKey {
    #[default]
    ChangeTab,
}

impl<'a> App<'a> {
    pub fn new(title: &'a str, enhanced_graphics: bool) -> Self {
        let mut rand_signal = RandomSignal::new(0, 100);
        let sparkline_points = rand_signal.by_ref().take(300).collect();
        let mut sin_signal = SinSignal::new(0.2, 3.0, 18.0);
        let sin1_points = sin_signal.by_ref().take(100).collect();
        let mut sin_signal2 = SinSignal::new(0.1, 2.0, 10.0);
        let sin2_points = sin_signal2.by_ref().take(200).collect();

        let mut effects = EffectManager::default();
        effects.add_effect(effects::startup());
        effects.add_effect(effects::pulsate_selected_tab());
        App {
            title,
            should_quit: false,
            tabs: TabsState::new(vec!["👋 ~/.config", "🧮 /etc/infra", "~/workspace"]),
            show_chart: true,
            progress: 0.0,
            sparkline: Signal {
                source: rand_signal,
                points: sparkline_points,
                tick_rate: 1,
            },
            tasks: StatefulList::with_items(TASKS.to_vec()),
            logs: StatefulList::with_items(LOGS.to_vec()),
            signals: Signals {
                sin1: Signal {
                    source: sin_signal,
                    points: sin1_points,
                    tick_rate: 5,
                },
                sin2: Signal {
                    source: sin_signal2,
                    points: sin2_points,
                    tick_rate: 10,
                },
                window: [0.0, 20.0],
            },
            barchart: EVENTS.to_vec(),
            servers: vec![
                // Surface Pro 7 — already provided
                Server {
                    user: "mfarabi",
                    hostname: "guix",
                    chassis: "Microsoft Surface Pro 7",
                    os: "GNU GUIX",
                    kernel: "Linux Libre",
                    display: "1366x768 @ 60Hz in 13\"",
                    desktop: "EXWM",
                    cpu: "Intel Core i5- @ GHz",
                    gpu: "Integrated (TBD)",
                    memory: "TBD",
                    disk: "TBD",
                    uptime: "TBD",
                    terminal: "TBD",
                    location: "Ottawa",
                    coords: (45.42, -75.00),
                    status: "Idle",
                },
                // ... other Surface entries ...
                Server {
                    user: "mfarabi",
                    hostname: "freebsd",
                    chassis: "HP EliteBook 820 G2",
                    os: "FreeBSD 14.3-RELEASE",
                    kernel: "FreeBSD 14.3-RELEASE",
                    display: "1366x768 @ 60Hz in 13\"",
                    desktop: "Hyprland",
                    cpu: "Intel Core i5-5300U(4) @ 2.29 GHz",
                    gpu: "Intel Device 1616",
                    memory: "16 GB",
                    disk: "0.5 TB",
                    uptime: "TBD",
                    terminal: "zsh + kitty",
                    location: "TBD",
                    coords: (0.0, 0.0),
                    status: "Up",
                },
                Server {
                    user: "mfarabi",
                    hostname: "mfarabi",
                    chassis: "MacBook Air M1 2020",
                    os: "macOS Sequoia",
                    kernel: "Darwin 24.5.0",
                    display: "2880x1800 @ 60Hz in 13\"",
                    desktop: "Quartz",
                    cpu: "Apple M1(8) @ 3.20 GHz",
                    gpu: "Apple M1(7)",
                    memory: "8 GB",
                    disk: "0.526 TB",
                    uptime: "TBD",
                    terminal: "zsh + kitty",
                    location: "TBD",
                    coords: (0.0, 0.0),
                    status: "Up",
                },
                Server {
                    user: "mfarabi",
                    hostname: "ubuntu",
                    chassis: "ASUS",
                    os: "FreeBSD 14.3-RELEASE",
                    kernel: "FreeBSD 14.3-RELEASE",
                    display: "1366x768 @ 60Hz in 13\"",
                    desktop: "Hyprland",
                    cpu: "Intel Core i5-5300U(4) @ 2.29 GHz",
                    gpu: "Intel Device 1616",
                    memory: "16 GB",
                    disk: "0.5 TB",
                    uptime: "TBD",
                    terminal: "zsh + kitty",
                    location: "TBD",
                    coords: (0.0, 0.0),
                    status: "Up",
                },
                Server {
                    user: "mfarabi",
                    hostname: "ubuntu",
                    chassis: "MSI GS65",
                    os: "Ubuntu 24.04",
                    kernel: "linux-6.8",
                    display: "TBD",
                    desktop: "N/A",
                    cpu: "TBD",
                    gpu: "TBD",
                    memory: "TBD",
                    disk: "TBD",
                    uptime: "TBD",
                    terminal: "zsh + kitty",
                    location: "TBD",
                    coords: (0.0, 0.0),
                    status: "Up",
                },
                Server {
                    user: "mfarabi",
                    hostname: "ubuntu",
                    chassis: "MSI GS76",
                    os: "Ubuntu 24.04",
                    kernel: "linux-6.8",
                    display: "TBD",
                    desktop: "N/A",
                    cpu: "TBD",
                    gpu: "TBD",
                    memory: "TBD",
                    disk: "TBD",
                    uptime: "TBD",
                    terminal: "zsh + kitty",
                    location: "TBD",
                    coords: (0.0, 0.0),
                    status: "Up",
                },
                Server {
                    user: "mfarabi",
                    hostname: "archlinux",
                    chassis: "Framework 16",
                    os: "Arch Linux",
                    kernel: "linux-6.15.2",
                    display: "2560x1600 @ 165Hz in 16\"",
                    desktop: "Hyprland",
                    cpu: "AMD Ryzen 9 7940HS @ 5.26 GHz",
                    gpu: "AMD Radeon RX 7700S & AMD Radeon 780M",
                    memory: "64 GB",
                    disk: "4 TB",
                    uptime: "41 mins",
                    terminal: "zsh + kitty",
                    location: "TBD",
                    coords: (0.0, 0.0),
                    status: "Up",
                },
                Server {
                    user: "TBD",
                    hostname: "TBD",
                    chassis: "TBD",
                    os: "NixOS",
                    kernel: "linux-6.15.2",
                    display: "N/A",
                    desktop: "N/A",
                    cpu: "TBD",
                    gpu: "TBD",
                    memory: "TBD",
                    disk: "TBD",
                    uptime: "TBD",
                    terminal: "TBD",
                    location: "TBD",
                    coords: (0.0, 0.0),
                    status: "Up",
                },
                Server {
                    user: "TBD",
                    hostname: "TBD",
                    chassis: "TBD",
                    os: "Windows + NixOS WSL",
                    kernel: "N/A",
                    display: "N/A",
                    desktop: "N/A",
                    cpu: "TBD",
                    gpu: "TBD",
                    memory: "TBD",
                    disk: "TBD",
                    uptime: "TBD",
                    terminal: "TBD",
                    location: "TBD",
                    coords: (0.0, 0.0),
                    status: "Down",
                },
                Server {
                    user: "mfarabi",
                    hostname: "stm32",
                    chassis: "STM32F3DISCOVERY",
                    os: "N/A",
                    kernel: "N/A",
                    display: "N/A",
                    desktop: "N/A",
                    cpu: "TBD",
                    gpu: "N/A",
                    memory: "N/A",
                    disk: "N/A",
                    uptime: "N/A",
                    terminal: "N/A",
                    location: "TBD",
                    coords: (0.0, 0.0),
                    status: "Idle",
                },
                Server {
                    user: "mfarabi",
                    hostname: "esp32",
                    chassis: "Espressif ESP32",
                    os: "N/A",
                    kernel: "N/A",
                    display: "N/A",
                    desktop: "N/A",
                    cpu: "TBD",
                    gpu: "N/A",
                    memory: "N/A",
                    disk: "N/A",
                    uptime: "N/A",
                    terminal: "N/A",
                    location: "TBD",
                    coords: (0.0, 0.0),
                    status: "Idle",
                },
                Server {
                    user: "mfarabi",
                    hostname: "arduino-uno",
                    chassis: "Arduino Uno",
                    os: "N/A",
                    kernel: "N/A",
                    display: "N/A",
                    desktop: "N/A",
                    cpu: "TBD",
                    gpu: "N/A",
                    memory: "N/A",
                    disk: "N/A",
                    uptime: "N/A",
                    terminal: "N/A",
                    location: "TBD",
                    coords: (0.0, 0.0),
                    status: "Idle",
                },
                Server {
                    user: "mfarabi",
                    hostname: "arduino-mega",
                    chassis: "Arduino Mega",
                    os: "N/A",
                    kernel: "N/A",
                    display: "N/A",
                    desktop: "N/A",
                    cpu: "TBD",
                    gpu: "N/A",
                    memory: "N/A",
                    disk: "N/A",
                    uptime: "N/A",
                    terminal: "N/A",
                    location: "TBD",
                    coords: (0.0, 0.0),
                    status: "Idle",
                },
                Server {
                    user: "mfarabi",
                    hostname: "rpi",
                    chassis: "Raspberry Pi B",
                    os: "TBD",
                    kernel: "TBD",
                    display: "N/A",
                    desktop: "N/A",
                    cpu: "TBD",
                    gpu: "TBD",
                    memory: "TBD",
                    disk: "TBD",
                    uptime: "TBD",
                    terminal: "TBD",
                    location: "TBD",
                    coords: (0.0, 0.0),
                    status: "Down",
                },
                Server {
                    user: "mfarabi",
                    hostname: "dlink",
                    chassis: "D-LINK DIR 1750",
                    os: "TBD",
                    kernel: "TBD",
                    display: "N/A",
                    desktop: "N/A",
                    cpu: "TBD",
                    gpu: "N/A",
                    memory: "TBD",
                    disk: "TBD",
                    uptime: "TBD",
                    terminal: "N/A",
                    location: "TBD",
                    coords: (0.0, 0.0),
                    status: "Down",
                },
            ],
            enhanced_graphics,
            effects,
            last_frame: web_time::Instant::now(),
        }
    }

    pub fn on_up(&mut self) {
        self.tasks.previous();
    }

    pub fn on_down(&mut self) {
        self.tasks.next();
    }

    pub fn on_right(&mut self) {
        self.tabs.next();
        self.add_transition_tab_effect();
    }

    pub fn on_left(&mut self) {
        self.tabs.previous();
        self.add_transition_tab_effect();
    }

    pub fn on_key(&mut self, c: char) {
        match c {
            'q' => {
                self.should_quit = true;
            }
            't' => {
                self.show_chart = !self.show_chart;
            }
            _ => {}
        }
    }

    pub fn on_tick(&mut self) -> Duration {
        // Update progress
        self.progress += 0.001;
        if self.progress > 1.0 {
            self.progress = 0.0;
        }

        self.sparkline.on_tick();
        self.signals.on_tick();

        let log = self.logs.items.pop().unwrap();
        self.logs.items.insert(0, log);

        let event = self.barchart.pop().unwrap();
        self.barchart.insert(0, event);

        // calculate elapsed time since last frame
        let now = web_time::Instant::now();
        let elapsed = now.duration_since(self.last_frame).as_millis() as u32;
        self.last_frame = now;

        Duration::from_millis(elapsed)
    }

    fn add_transition_tab_effect(&mut self) {
        let effect = effects::change_tab();
        self.effects.add_unique_effect(EffectKey::ChangeTab, effect);
    }
}
