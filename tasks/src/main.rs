use std::{sync::Arc, time::Duration};

use anyhow::{Context, Result};
use headless_chrome::{Browser, Tab, browser::LaunchOptions, protocol::cdp::Page};

mod selectors;

#[derive(Clone, Debug)]
struct Contact {
    name: String,
    email: String,
    phone: String,
}

#[derive(Clone, Debug)]
struct TimeWindow {
    start_text: String,
    end_text: String,
}

#[derive(Clone, Debug)]
struct ParkingConfig {
    base_url: String,
    license_plate: String,
    apartment: String,
    passcode: String,
    vehicle_make_model_color: String,
    contact: Contact,
    window: TimeWindow,
    email_confirmation_only: bool,
}

impl Default for ParkingConfig {
    fn default() -> Self {
        Self {
            base_url: "https://talismanon.parkingattendant.com/talismanon/services".into(),
            license_plate: "ABCD 123".into(),
            apartment: "820-606".into(),
            passcode: "123456".into(),
            vehicle_make_model_color: "Toyota Corolla 2020".into(),
            contact: Contact {
                name: "Jane doe".into(),
                email: "jane-doe@gmail.com".into(),
                phone: "6131231234".into(),
            },
            window: TimeWindow {
                start_text: "Sun Oct 26 8:00 PM".into(),
                end_text: "Mon Oct 27 8:00 AM".into(),
            },
            email_confirmation_only: false,
        }
    }
}

fn screenshot(tab: &Tab, name: &str) -> Result<()> {
    let data = tab.capture_screenshot(Page::CaptureScreenshotFormatOption::Png, None, None, true)?;
    std::fs::write(name, data).with_context(|| format!("write screenshot {}", name))?;
    Ok(())
}

fn wait_then_click(tab: &Tab, selector: &str) -> Result<()> {
    tab.wait_for_element(selector)?.click()?;
    Ok(())
}

fn wait_clear_type(tab: &Tab, selector: &str, text: &str) -> Result<()> {
    let el = tab.wait_for_element(selector)?;
    el.click()?;
    // tab.press_key("Meta+A").ok();
    // tab.press_key("Control+A").ok();
    tab.type_str(text)?;
    Ok(())
}

fn set_date_time(tab: &Tab, trigger_selector: &str, input_selector: &str, value: &str) -> Result<()> {
    wait_then_click(tab, trigger_selector)?;
    wait_clear_type(tab, input_selector, value)?;
    tab.press_key("Enter").ok();
    if tab.find_element(selectors::DATE_TIME_SAVE).is_ok() {
        wait_then_click(tab, selectors::DATE_TIME_SAVE)?;
    }
    Ok(())
}

fn wait_for_visible(tab: &Tab, selector: &str, timeout: Duration) -> Result<()> {
    tab.wait_for_element_with_custom_timeout(selector, timeout)?;
    Ok(())
}

struct ParkingBot {
    browser: Browser,
    tab: Arc<Tab>,
    cfg: ParkingConfig,
}

impl ParkingBot {
    fn new(cfg: ParkingConfig) -> Result<Self> {
        let launch = LaunchOptions {
            headless: false,
            devtools: false,
            window_size: Some((1280, 900)),
            ..Default::default()
        };
        let browser = Browser::new(launch)?;
        let tab = browser.new_tab()?;
        tab.set_default_timeout(Duration::from_secs(15));
        Ok(Self { browser, tab, cfg })
    }

    fn run(self) -> Result<()> {
        self.open()?;
        self.enter_flow()?;
        self.fill_vehicle_and_unit()?;
        // self.set_window()?;
        self.fill_contact()?;
        self.set_confirmation_mode()?;
        // screenshot(&self.tab, "before-submit.png").ok();
        // self.submit()?;
        // self.verify_success()?;
        // screenshot(&self.tab, "success.png").ok();
        Ok(())
    }

    fn open(&self) -> Result<()> {
        self.tab.navigate_to(&self.cfg.base_url)?.wait_until_navigated()?;
        Ok(())
    }

    fn enter_flow(&self) -> Result<()> {
        wait_then_click(&self.tab, selectors::CTA_ISSUE_TICKET)?;
        self.tab.wait_for_element_with_custom_timeout("body", Duration::from_secs(2))?;
        Ok(())
    }

    fn fill_vehicle_and_unit(&self) -> Result<()> {
        wait_clear_type(&self.tab, selectors::LICENSE_PLATE, &self.cfg.license_plate)?;
        wait_clear_type(&self.tab, selectors::APARTMENT, &self.cfg.apartment)?;
        wait_clear_type(&self.tab, selectors::PASSCODE, &self.cfg.passcode)?;
        wait_clear_type(&self.tab, selectors::VEHICLE_INFO, &self.cfg.vehicle_make_model_color)?;
        Ok(())
    }

    fn set_window(&self) -> Result<()> {
        set_date_time(&self.tab, selectors::START_CHANGE, selectors::START_INPUT, &self.cfg.window.start_text)?;
        set_date_time(&self.tab, selectors::END_CHANGE, selectors::END_INPUT, &self.cfg.window.end_text)?;
        Ok(())
    }

    fn fill_contact(&self) -> Result<()> {
        wait_clear_type(&self.tab, selectors::CONTACT_NAME, &self.cfg.contact.name)?;
        wait_clear_type(&self.tab, selectors::CONTACT_EMAIL, &self.cfg.contact.email)?;
        wait_clear_type(&self.tab, selectors::CONTACT_PHONE, &self.cfg.contact.phone)?;
        Ok(())
    }

    fn set_confirmation_mode(&self) -> Result<()> {
        if self.cfg.email_confirmation_only {
            if self.tab.find_element(selectors::CONFIRMATION_MODE_CHANGE).is_ok() {
                wait_then_click(&self.tab, selectors::CONFIRMATION_MODE_CHANGE)?;
            }
            if self.tab.find_element(selectors::CONFIRMATION_EMAIL_ONLY).is_ok() {
                wait_then_click(&self.tab, selectors::CONFIRMATION_EMAIL_ONLY)?;
            }
        }
        Ok(())
    }

    fn submit(&self) -> Result<()> {
        wait_for_visible(&self.tab, selectors::SUBMIT, Duration::from_secs(5))?;
        wait_then_click(&self.tab, selectors::SUBMIT)?;
        Ok(())
    }

    fn verify_success(&self) -> Result<()> {
        wait_for_visible(&self.tab, selectors::SUCCESS_MARKER, Duration::from_secs(20)).context("did not see success marker")?;
        Ok(())
    }
}

fn main() -> Result<()> {
    let cfg = ParkingConfig::default();
    ParkingBot::new(cfg)?.run()
}
