use playwright_rs::{AriaRole, FilterOptions, GetByRoleOptions, Page};

pub enum Locator {
    Css(String),
    Text { text: String, exact: bool },
    Role(AriaRole, GetByRoleOptions),
    Title { text: String, exact: bool },
    Placeholder { text: String, exact: bool },
    Label { text: String, exact: bool },
    Scoped(Box<Locator>, Box<Locator>),
    First(Box<Locator>),
    Last(Box<Locator>),
    Nth(Box<Locator>, i32),
    Filtered {
        base: Box<Locator>,
        has_text: Option<String>,
        has_not_text: Option<String>,
    },
}

pub struct RoleBuilder {
    role: AriaRole,
    opts: GetByRoleOptions,
}

impl RoleBuilder {
    pub fn name(mut self, name: &str) -> Self {
        self.opts.name = Some(name.into());
        self
    }

    pub fn level(mut self, level: u32) -> Self {
        self.opts.level = Some(level);
        self
    }

    pub fn checked(mut self, checked: bool) -> Self {
        self.opts.checked = Some(checked);
        self
    }

    pub fn disabled(mut self, disabled: bool) -> Self {
        self.opts.disabled = Some(disabled);
        self
    }

    pub fn expanded(mut self, expanded: bool) -> Self {
        self.opts.expanded = Some(expanded);
        self
    }

    pub fn pressed(mut self, pressed: bool) -> Self {
        self.opts.pressed = Some(pressed);
        self
    }

    pub fn exact(mut self) -> Self {
        self.opts.exact = Some(true);
        self
    }

    pub fn include_hidden(mut self) -> Self {
        self.opts.include_hidden = Some(true);
        self
    }

    pub fn build(self) -> Locator {
        Locator::Role(self.role, self.opts)
    }
}

impl From<RoleBuilder> for Locator {
    fn from(rb: RoleBuilder) -> Self {
        rb.build()
    }
}

fn role_opts_to_pw(opts: &GetByRoleOptions) -> Option<GetByRoleOptions> {
    let is_default = opts.name.is_none()
        && opts.level.is_none()
        && opts.checked.is_none()
        && opts.disabled.is_none()
        && opts.selected.is_none()
        && opts.expanded.is_none()
        && opts.include_hidden.is_none()
        && opts.exact.is_none()
        && opts.pressed.is_none();

    if is_default { None } else { Some(opts.clone()) }
}

impl Locator {
    pub fn role(role: AriaRole) -> RoleBuilder {
        RoleBuilder {
            role,
            opts: GetByRoleOptions::default(),
        }
    }

    pub fn text(t: &str) -> Self {
        Self::Text { text: t.into(), exact: false }
    }

    pub fn exact_text(t: &str) -> Self {
        Self::Text { text: t.into(), exact: true }
    }

    pub fn title(t: &str) -> Self {
        Self::Title { text: t.into(), exact: true }
    }

    pub fn placeholder(t: &str) -> Self {
        Self::Placeholder { text: t.into(), exact: false }
    }

    pub fn label(t: &str) -> Self {
        Self::Label { text: t.into(), exact: false }
    }

    pub fn exact_label(t: &str) -> Self {
        Self::Label { text: t.into(), exact: true }
    }

    pub fn scoped(parent: Locator, child: Locator) -> Self {
        Self::Scoped(Box::new(parent), Box::new(child))
    }

    pub fn first(self) -> Self {
        Self::First(Box::new(self))
    }

    pub fn last(self) -> Self {
        Self::Last(Box::new(self))
    }

    pub fn nth(self, n: i32) -> Self {
        Self::Nth(Box::new(self), n)
    }

    pub fn filter_has_text(self, text: &str) -> Self {
        Self::Filtered {
            base: Box::new(self),
            has_text: Some(text.into()),
            has_not_text: None,
        }
    }

    pub fn filter_has_not_text(self, text: &str) -> Self {
        Self::Filtered {
            base: Box::new(self),
            has_text: None,
            has_not_text: Some(text.into()),
        }
    }

    pub fn resolve<'a>(
        &'a self,
        page: &'a Page,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = playwright_rs::Locator> + 'a>> {
        Box::pin(async move {
            match self {
                Self::Scoped(parent, child) => {
                    let p = parent.resolve(page).await;
                    child.resolve_in(&p)
                }
                Self::First(inner) => inner.resolve(page).await.first(),
                Self::Last(inner) => inner.resolve(page).await.last(),
                Self::Nth(inner, n) => inner.resolve(page).await.nth(*n),
                Self::Filtered { base, has_text, has_not_text } => {
                    base.resolve(page).await.filter(FilterOptions {
                        has_text: has_text.clone(),
                        has_not_text: has_not_text.clone(),
                        has: None,
                        has_not: None,
                    })
                }
                _ => self.resolve_leaf(page).await,
            }
        })
    }

    async fn resolve_leaf(&self, page: &Page) -> playwright_rs::Locator {
        match self {
            Self::Css(s) => page.locator(s).await,
            Self::Text { text, exact } => page.get_by_text(text, *exact).await,
            Self::Role(role, opts) => page.get_by_role(*role, role_opts_to_pw(opts)).await,
            Self::Title { text, exact } => page.get_by_title(text, *exact).await,
            Self::Placeholder { text, exact } => page.get_by_placeholder(text, *exact).await,
            Self::Label { text, exact } => page.get_by_label(text, *exact).await,
            _ => unreachable!(),
        }
    }

    fn resolve_in(&self, parent: &playwright_rs::Locator) -> playwright_rs::Locator {
        match self {
            Self::Css(s) => parent.locator(s),
            Self::Text { text, exact } => parent.get_by_text(text, *exact),
            Self::Role(role, opts) => parent.get_by_role(*role, role_opts_to_pw(opts)),
            Self::Title { text, exact } => parent.get_by_title(text, *exact),
            Self::Placeholder { text, exact } => parent.get_by_placeholder(text, *exact),
            Self::Label { text, exact } => parent.get_by_label(text, *exact),
            Self::Scoped(p, c) => {
                let mid = p.resolve_in(parent);
                c.resolve_in(&mid)
            }
            Self::First(inner) => inner.resolve_in(parent).first(),
            Self::Last(inner) => inner.resolve_in(parent).last(),
            Self::Nth(inner, n) => inner.resolve_in(parent).nth(*n),
            Self::Filtered { base, has_text, has_not_text } => {
                base.resolve_in(parent).filter(FilterOptions {
                    has_text: has_text.clone(),
                    has_not_text: has_not_text.clone(),
                    has: None,
                    has_not: None,
                })
            }
        }
    }
}

// ===== LAYOUT: NAVBAR =====

pub mod navbar {
    use super::{AriaRole, Locator};

    pub fn root() -> Locator {
        Locator::Css("header".into())
    }

    pub fn logo() -> Locator {
        Locator::scoped(root(), Locator::role(AriaRole::Link).build())
    }

    pub fn search_button() -> Locator {
        Locator::role(AriaRole::Button).name("Search...").build()
    }

    pub fn wifi_button() -> Locator {
        Locator::Css("button[aria-label='Network settings']".into())
    }

    pub fn skeleton_badges() -> Locator {
        Locator::scoped(root(), Locator::Css(".animate-pulse".into())).first()
    }

    pub fn chip_badge() -> Locator {
        Locator::scoped(root(), Locator::Text { text: "ESP32".into(), exact: false })
    }

    pub fn memory_badge() -> Locator {
        Locator::scoped(root(), Locator::Css("span.font-mono".into())).last()
    }
}

// ===== LAYOUT: FOOTER =====

pub mod footer {
    use super::Locator;

    pub fn root() -> Locator {
        Locator::Css("footer".into())
    }

    pub fn company_name() -> Locator {
        Locator::scoped(root(), Locator::text("Apidae Systems"))
    }

    pub fn website_link() -> Locator {
        Locator::scoped(root(), Locator::title("Website"))
    }

    pub fn linkedin_link() -> Locator {
        Locator::scoped(root(), Locator::title("LinkedIn"))
    }

    pub fn github_link() -> Locator {
        Locator::scoped(root(), Locator::title("GitHub"))
    }
}

// ===== HOME: URL BAR =====

pub mod url_bar {
    use super::{AriaRole, Locator};

    pub fn protocol_toggle() -> Locator {
        Locator::role(AriaRole::Button).name("http").build()
    }

    pub fn hostname_input() -> Locator {
        Locator::Css("input[aria-label='Device URL']".into())
    }

    pub fn connection_status() -> Locator {
        Locator::Css("div[aria-label='POLLING'], div[aria-label='LIVE'], div[aria-label*='.']".into())
    }

    pub fn live_status() -> Locator {
        Locator::Css("div[aria-label='LIVE'], div[aria-label='POLLING'], div[aria-label*='.']".into())
    }
}

// ===== HOME: MEASUREMENT =====

pub mod measurement {
    use super::{AriaRole, Locator};

    pub fn root() -> Locator {
        Locator::Css("#cloudevents-section".into())
    }

    pub fn tab(label: &str) -> Locator {
        Locator::scoped(root(), Locator::role(AriaRole::Tab).name(label).build())
    }

    pub fn temp_humidity_tab() -> Locator {
        Locator::role(AriaRole::Tab).name("Temp/Humidity").build()
    }

    pub fn voltage_tab() -> Locator {
        Locator::role(AriaRole::Tab).name("Voltage").build()
    }

    pub fn co2_tab() -> Locator {
        Locator::role(AriaRole::Tab).name("CO\u{2082}").build()
    }

    pub fn empty_state() -> Locator {
        Locator::scoped(root(), Locator::text("No readings yet"))
    }

    pub fn sample_button() -> Locator {
        Locator::role(AriaRole::Button).name("Sample").build()
    }

    pub fn csv_button() -> Locator {
        Locator::role(AriaRole::Button).name("CSV").exact().build()
    }
}

// ===== HOME: SLEEP =====

pub mod sleep {
    use super::{AriaRole, Locator};

    pub fn root() -> Locator {
        Locator::Css("#sleep-panel".into())
    }

    pub fn heading() -> Locator {
        Locator::scoped(root(), Locator::text("Deep Sleep"))
    }

    pub fn wake_cause_badge() -> Locator {
        Locator::scoped(root(), Locator::text("power_on"))
    }

    pub fn preset_button(label: &str) -> Locator {
        Locator::scoped(
            root(),
            Locator::role(AriaRole::Button).name(label).exact().build(),
        )
    }

    pub fn custom_button() -> Locator {
        preset_button("custom")
    }

    pub fn hours_input() -> Locator {
        Locator::scoped(root(), Locator::label("Hours"))
    }

    pub fn minutes_input() -> Locator {
        Locator::scoped(root(), Locator::label("Minutes"))
    }

    pub fn seconds_input() -> Locator {
        Locator::scoped(root(), Locator::label("Seconds"))
    }

    pub fn toggle() -> Locator {
        Locator::scoped(root(), Locator::role(AriaRole::Switch).build())
    }
}

// ===== HOME: FILESYSTEM =====

pub mod filesystem {
    use super::{AriaRole, Locator};

    pub fn root() -> Locator {
        Locator::Css("#filesystem-section".into())
    }

    pub fn heading() -> Locator {
        Locator::scoped(root(), Locator::text("Filesystem"))
    }

    pub fn sd_section() -> Locator {
        Locator::scoped(root(), Locator::text("SD"))
    }

    pub fn littlefs_section() -> Locator {
        Locator::scoped(root(), Locator::text("LittleFS"))
    }

    pub fn file_row(filename: &str) -> Locator {
        Locator::scoped(root(), Locator::text(filename))
    }

    pub fn add_file_label() -> Locator {
        Locator::scoped(root(), Locator::text("Add file...")).first()
    }

    pub fn rename_button(filename: &str) -> Locator {
        Locator::scoped(root(), Locator::Css(format!("button[aria-label='Rename {filename}']")))
    }

    pub fn delete_button(filename: &str) -> Locator {
        Locator::scoped(root(), Locator::Css(format!("button[aria-label='Delete {filename}']")))
    }

    pub fn delete_dialog() -> Locator {
        Locator::role(AriaRole::Alertdialog).build()
    }

    pub fn rename_dialog() -> Locator {
        Locator::role(AriaRole::Alertdialog).build()
    }

    pub fn dialog_cancel() -> Locator {
        Locator::role(AriaRole::Button).name("Cancel").build()
    }

    pub fn dialog_delete() -> Locator {
        Locator::role(AriaRole::Button).name("Delete").exact().build()
    }

    pub fn dialog_rename() -> Locator {
        Locator::role(AriaRole::Button).name("Rename").exact().build()
    }

    pub fn rename_input() -> Locator {
        Locator::label("New filename")
    }

    pub fn csv_preview_dialog() -> Locator {
        Locator::role(AriaRole::Dialog).build()
    }

    pub fn preview_close() -> Locator {
        Locator::role(AriaRole::Button).name("Close").build()
    }
}

// ===== HOME: TERMINAL =====

pub mod terminal {
    use super::Locator;

    pub fn root() -> Locator {
        Locator::Css("#terminal-container".into())
    }
}

// ===== HOME: FLASH =====

pub mod flash {
    use super::{AriaRole, Locator};

    pub fn root() -> Locator {
        Locator::Css("#flash-panel".into())
    }

    pub fn heading() -> Locator {
        Locator::scoped(root(), Locator::text("Firmware Update"))
    }

    pub fn connect_button() -> Locator {
        Locator::scoped(root(), Locator::role(AriaRole::Button).name("Connect").build())
    }

    pub fn disconnect_button() -> Locator {
        Locator::scoped(root(), Locator::role(AriaRole::Button).name("Disconnect").build())
    }

    pub fn flash_button() -> Locator {
        Locator::scoped(root(), Locator::role(AriaRole::Button).name("Flash Firmware").build())
    }

    pub fn monitor_button() -> Locator {
        Locator::scoped(root(), Locator::role(AriaRole::Button).name("Monitor").build())
    }

    pub fn firmware_section() -> Locator {
        Locator::scoped(root(), Locator::text("Select a firmware"))
    }
}

// ===== COMMAND PALETTE =====

pub mod command_palette {
    use super::{AriaRole, Locator};

    pub fn root() -> Locator {
        Locator::role(AriaRole::Dialog).build()
    }

    pub fn search_input() -> Locator {
        Locator::Css("input[aria-label='Search commands']".into())
    }

    pub fn command(label: &str) -> Locator {
        Locator::role(AriaRole::Button).name(label).build()
    }
}

// ===== NETWORK SHEET =====

pub mod network_sheet {
    use super::{AriaRole, Locator};

    pub fn root() -> Locator {
        Locator::Css("div[role='dialog'][aria-label='Network settings']".into())
    }

    pub fn scan_button() -> Locator {
        Locator::scoped(root(), Locator::role(AriaRole::Button).name("Scan").build())
    }

    pub fn ssid_input() -> Locator {
        Locator::Css("#network-ssid-input".into())
    }

    pub fn password_input() -> Locator {
        Locator::Css("#network-password-input".into())
    }

    pub fn connect_button() -> Locator {
        Locator::scoped(root(), Locator::role(AriaRole::Button).name("Connect").build())
    }

    pub fn close_button() -> Locator {
        Locator::scoped(root(), Locator::Css("button[aria-label='Close']".into()))
    }

    pub fn results_region() -> Locator {
        Locator::scoped(root(), Locator::text("RSSI"))
    }
}

// ===== 404 =====

pub mod not_found {
    use super::{AriaRole, Locator};

    pub fn heading() -> Locator {
        Locator::role(AriaRole::Heading).level(1).build()
    }

    pub fn subheading() -> Locator {
        Locator::role(AriaRole::Heading).level(2).build()
    }

    pub fn back_home_button() -> Locator {
        Locator::text("Back to Home")
    }
}

// ===== DOCS =====

pub mod docs {
    use super::{AriaRole, Locator};

    pub fn sidebar() -> Locator {
        Locator::role(AriaRole::Navigation).build()
    }

    pub fn content() -> Locator {
        Locator::Css("article".into())
    }
}
