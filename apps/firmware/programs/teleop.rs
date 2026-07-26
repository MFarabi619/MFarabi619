use core::{
    f32::consts::FRAC_1_SQRT_2,
    ffi::{c_char, c_int, c_void, CStr},
};

use log::{info, warn};
use oh_my_zephyr::{sys_clock_gettime, Timespec};
use static_cell::StaticCell;
use zephyr::{
    raw::{
        self, net_if_get_wifi_sta, net_mgmt_NET_REQUEST_WIFI_PS, sys_rand_get,
        wifi_ps_params, wifi_ps_WIFI_PS_DISABLED,
    },
    sync::{
        atomic::{AtomicI64, AtomicU32, Ordering},
        SpinMutex,
    },
    time::{sleep, Duration},
};

use crate::networking::wifi;

extern "C" {
    fn teleop_zenoh_open(locator: *const c_char) -> c_int;
    fn teleop_zenoh_close();
    fn teleop_zenoh_declare_publisher(keyexpr: *const c_char) -> c_int;
    fn teleop_zenoh_publish(
        payload: *const u8,
        payload_length: usize,
        attachment: *const u8,
        attachment_length: usize,
    );
}

macro_rules! zenoh_locator {
    () => {
        "tcp/10.0.0.222:7447"
    };
}

const ZENOH_LOCATOR: &str = concat!(zenoh_locator!(), "\0");
// rmw_zenoh keyexpr: <domain>/<topic>/<dds type>/<hash>; hash from
// `ros2 topic info /joy_teleop/cmd_vel --verbose` against the robot.
const CMD_VEL_KEYEXPR: &CStr = c"0/joy_teleop/cmd_vel/geometry_msgs::msg::dds_::TwistStamped_/RIHS01_5f0fcd4f81d5d06ad9b4c4c63e3ea51b82d6ae4d0558f1d475229b1121db6f64";

const STOP_SYMBOL: &str = concat!("\u{F04D}", "\0");

const LINEAR_SPEED: f64 = 1.0;
const ANGULAR_SPEED: f64 = 1.0;

const PUBLISH_PERIOD_MS: u32 = 200;
const STATUS_REFRESH_PERIOD_MS: u32 = 500;
const RECONNECT_DELAY_MS: u64 = 2000;
const WIFI_WAIT_PERIOD_SECS: u64 = 30;
const LVGL_INIT_POLL_PERIOD_MS: u64 = 50;
const SYS_CLOCK_REALTIME: c_int = 1;

#[derive(Clone, Copy, PartialEq)]
#[repr(u32)]
enum LinkState {
    WaitingForNetwork = 0,
    Connecting = 1,
    Ready = 2,
}

impl LinkState {
    fn status_text(self) -> &'static str {
        match self {
            LinkState::WaitingForNetwork => concat!("wifi \u{F021}", "\0"),
            LinkState::Connecting => concat!("zenoh \u{F021}", "\0"),
            LinkState::Ready => concat!("\u{F1EB} ", zenoh_locator!(), "\0"),
        }
    }
}

static LINK_STATE: AtomicU32 = AtomicU32::new(LinkState::WaitingForNetwork as u32);

fn set_link_state(state: LinkState) {
    LINK_STATE.store(state as u32, Ordering::Release);
}

fn link_state() -> LinkState {
    match LINK_STATE.load(Ordering::Acquire) {
        state if state == LinkState::Connecting as u32 => LinkState::Connecting,
        state if state == LinkState::Ready as u32 => LinkState::Ready,
        _ => LinkState::WaitingForNetwork,
    }
}

#[derive(Clone, Copy)]
struct DriveCommand {
    linear_x: f64,
    angular_z: f64,
}

impl DriveCommand {
    const STOP: DriveCommand = DriveCommand {
        linear_x: 0.0,
        angular_z: 0.0,
    };
}

// geometry_msgs/TwistStamped in XCDR1 little-endian; alignment is relative
// to the byte after the 4-byte encapsulation header.
const CDR_ENCAPSULATION_HEADER_BYTES: usize = 4;
const STAMP_SEC_OFFSET: usize = CDR_ENCAPSULATION_HEADER_BYTES;
const STAMP_NANOSEC_OFFSET: usize = CDR_ENCAPSULATION_HEADER_BYTES + 4;
const FRAME_ID_LENGTH_OFFSET: usize = CDR_ENCAPSULATION_HEADER_BYTES + 8;
const FRAME_ID_OFFSET: usize = CDR_ENCAPSULATION_HEADER_BYTES + 12;
const TWIST_OFFSET: usize = CDR_ENCAPSULATION_HEADER_BYTES + 24;
const TWIST_LINEAR_X_OFFSET: usize = TWIST_OFFSET;
const TWIST_ANGULAR_Z_OFFSET: usize = TWIST_OFFSET + 5 * 8;
const TWIST_STAMPED_CDR_BYTES: usize = TWIST_OFFSET + 6 * 8;

const FRAME_ID: &[u8] = b"base_link\0";

// rmw_zenoh attachment: seq i64 LE, source timestamp ns i64 LE, 0x10, gid.
const ATTACHMENT_GID_BYTES: usize = 16;
const ATTACHMENT_BYTES: usize = 8 + 8 + 1 + ATTACHMENT_GID_BYTES;

const _: () = assert!(FRAME_ID_OFFSET + FRAME_ID.len() <= TWIST_OFFSET);
const _: () = assert!((TWIST_OFFSET - CDR_ENCAPSULATION_HEADER_BYTES) % 8 == 0);

static SEQUENCE_NUMBER: AtomicI64 = AtomicI64::new(0);
static ATTACHMENT_GID: SpinMutex<[u8; ATTACHMENT_GID_BYTES]> =
    SpinMutex::new([0; ATTACHMENT_GID_BYTES]);

fn encode_twist_stamped(
    out: &mut [u8; TWIST_STAMPED_CDR_BYTES],
    stamp_sec: i32,
    stamp_nanosec: u32,
    command: DriveCommand,
) {
    out[1] = 0x01; // CDR little-endian

    out[STAMP_SEC_OFFSET..][..4].copy_from_slice(&stamp_sec.to_le_bytes());
    out[STAMP_NANOSEC_OFFSET..][..4].copy_from_slice(&stamp_nanosec.to_le_bytes());
    out[FRAME_ID_LENGTH_OFFSET..][..4]
        .copy_from_slice(&(FRAME_ID.len() as u32).to_le_bytes());
    out[FRAME_ID_OFFSET..][..FRAME_ID.len()].copy_from_slice(FRAME_ID);
    out[TWIST_LINEAR_X_OFFSET..][..8].copy_from_slice(&command.linear_x.to_le_bytes());
    out[TWIST_ANGULAR_Z_OFFSET..][..8].copy_from_slice(&command.angular_z.to_le_bytes());
}

fn encode_attachment(
    out: &mut [u8; ATTACHMENT_BYTES],
    source_timestamp_nanoseconds: i64,
    gid: &[u8; ATTACHMENT_GID_BYTES],
) {
    let sequence_number = SEQUENCE_NUMBER.fetch_add(1, Ordering::Relaxed) + 1;
    out[..8].copy_from_slice(&sequence_number.to_le_bytes());
    out[8..16].copy_from_slice(&source_timestamp_nanoseconds.to_le_bytes());
    out[16] = ATTACHMENT_GID_BYTES as u8;
    out[17..].copy_from_slice(gid);
}

fn publish_command(command: DriveCommand) {
    if link_state() != LinkState::Ready {
        return;
    }

    let mut wall_clock = Timespec::default();
    unsafe { sys_clock_gettime(SYS_CLOCK_REALTIME, &mut wall_clock) };
    let source_timestamp_nanoseconds =
        wall_clock.tv_sec * 1_000_000_000 + wall_clock.tv_nsec as i64;

    let mut twist_stamped = [0u8; TWIST_STAMPED_CDR_BYTES];
    encode_twist_stamped(
        &mut twist_stamped,
        wall_clock.tv_sec as i32,
        wall_clock.tv_nsec as u32,
        command,
    );

    let gid = *ATTACHMENT_GID.lock().unwrap();
    let mut attachment = [0u8; ATTACHMENT_BYTES];
    encode_attachment(&mut attachment, source_timestamp_nanoseconds, &gid);

    unsafe {
        teleop_zenoh_publish(
            twist_stamped.as_ptr(),
            TWIST_STAMPED_CDR_BYTES,
            attachment.as_ptr(),
            ATTACHMENT_BYTES,
        );
    }
}

// Modem-sleep batches packets at DTIM intervals; the resulting latency
// spikes overrun the robot's 0.5 s command timeouts and chop the drive.
fn disable_wifi_power_save() {
    let station = unsafe { net_if_get_wifi_sta() };
    if station.is_null() {
        return;
    }
    let mut params: wifi_ps_params = unsafe { core::mem::zeroed() };
    params.enabled = wifi_ps_WIFI_PS_DISABLED;
    let result = unsafe {
        net_mgmt_NET_REQUEST_WIFI_PS(
            0,
            station,
            &mut params as *mut _ as *mut c_void,
            core::mem::size_of::<wifi_ps_params>(),
        )
    };
    if result < 0 {
        warn!("teleop: wifi ps off failed ({result})");
    }
}

pub fn network_thread_body() {
    {
        let mut gid = ATTACHMENT_GID.lock().unwrap();
        unsafe { sys_rand_get(gid.as_mut_ptr() as *mut c_void, ATTACHMENT_GID_BYTES) };
    }

    loop {
        while let Err(error) = wifi::sta::wait_for_ipv4(Duration::secs(WIFI_WAIT_PERIOD_SECS))
        {
            warn!("teleop: wait for ipv4: {error}");
        }
        disable_wifi_power_save();
        set_link_state(LinkState::Connecting);

        let open_result =
            unsafe { teleop_zenoh_open(ZENOH_LOCATOR.as_ptr() as *const c_char) };
        if open_result != 0 {
            warn!("teleop: z_open failed ({open_result}), retrying");
            set_link_state(LinkState::WaitingForNetwork);
            sleep(Duration::millis(RECONNECT_DELAY_MS));
            continue;
        }

        let declare_result =
            unsafe { teleop_zenoh_declare_publisher(CMD_VEL_KEYEXPR.as_ptr()) };
        if declare_result != 0 {
            warn!("teleop: declare_publisher failed ({declare_result}), retrying");
            unsafe { teleop_zenoh_close() };
            set_link_state(LinkState::WaitingForNetwork);
            sleep(Duration::millis(RECONNECT_DELAY_MS));
            continue;
        }
        break;
    }

    info!("teleop: publishing on {}", CMD_VEL_KEYEXPR.to_str().unwrap());
    set_link_state(LinkState::Ready);
}

const PAD_GRID_SIZE: usize = 3;
const ARROW_BOX_SIZE: i32 = 40;
const PAD_SIZE: i32 = 368;
const PAD_PADDING: i32 = 4;
const CELL_RADIUS: i32 = 6;
const ARROW_LINE_WIDTH: i32 = 4;
const STATUS_TOP_MARGIN: i32 = 8;

const GRUVBOX_BACKGROUND: u32 = 0x282828;
const GRUVBOX_CELL: u32 = 0x3c3836;
const GRUVBOX_CELL_BORDER: u32 = 0x665c54;
const GRUVBOX_CELL_PRESSED: u32 = 0x504945;
const GRUVBOX_CELL_PRESSED_BORDER: u32 = 0xfe8019;
const GRUVBOX_ARROW: u32 = 0xebdbb2;
const GRUVBOX_STOP: u32 = 0xfb4934;
const GRUVBOX_STATUS: u32 = 0x928374;

// LV_OPA_TRANSP is an anonymous-enum value bindgen does not export.
const OPA_TRANSPARENT: u8 = 0;

const GRID_FRACTION_UNIT: i32 = (raw::LV_GRID_TEMPLATE_LAST - 100 + 1) as i32;
static COLUMN_TEMPLATE: [i32; 4] = [
    GRID_FRACTION_UNIT,
    GRID_FRACTION_UNIT,
    GRID_FRACTION_UNIT,
    raw::LV_GRID_TEMPLATE_LAST as i32,
];
static ROW_TEMPLATE: [i32; 4] = COLUMN_TEMPLATE;

// Arrow polyline: shaft, then both head strokes through the tip. Glyph
// rotation would render each arrow through an ~8 KB intermediate layer,
// which the LVGL pool cannot hold.
const ARROW_OUTLINE: [(f32, f32); 5] =
    [(0.0, 16.0), (0.0, -16.0), (-10.0, -6.0), (0.0, -16.0), (10.0, -6.0)];
const ARROW_POINT_COUNT: usize = ARROW_OUTLINE.len();

// (sine, cosine) of the arrow heading, up = 0 degrees, clockwise.
#[derive(Clone, Copy)]
struct ArrowHeading {
    sine: f32,
    cosine: f32,
}

#[derive(Clone, Copy)]
struct PadCell {
    command: DriveCommand,
    arrow_heading: Option<ArrowHeading>,
}

impl PadCell {
    const fn arrow(linear_x: f64, angular_z: f64, sine: f32, cosine: f32) -> PadCell {
        PadCell {
            command: DriveCommand { linear_x, angular_z },
            arrow_heading: Some(ArrowHeading { sine, cosine }),
        }
    }

    const fn stop() -> PadCell {
        PadCell {
            command: DriveCommand::STOP,
            arrow_heading: None,
        }
    }
}

const DIAGONAL_COMPONENT: f32 = FRAC_1_SQRT_2;
const PAD_CELLS: [[PadCell; PAD_GRID_SIZE]; PAD_GRID_SIZE] = [
    [
        PadCell::arrow(1.0, 1.0, -DIAGONAL_COMPONENT, DIAGONAL_COMPONENT),
        PadCell::arrow(1.0, 0.0, 0.0, 1.0),
        PadCell::arrow(1.0, -1.0, DIAGONAL_COMPONENT, DIAGONAL_COMPONENT),
    ],
    [
        PadCell::arrow(0.0, 1.0, -1.0, 0.0),
        PadCell::stop(),
        PadCell::arrow(0.0, -1.0, 1.0, 0.0),
    ],
    [
        PadCell::arrow(-1.0, 1.0, -DIAGONAL_COMPONENT, -DIAGONAL_COMPONENT),
        PadCell::arrow(-1.0, 0.0, 0.0, -1.0),
        PadCell::arrow(-1.0, -1.0, DIAGONAL_COMPONENT, -DIAGONAL_COMPONENT),
    ],
];

static HELD_COMMAND: SpinMutex<DriveCommand> = SpinMutex::new(DriveCommand::STOP);

static ARROW_POINTS: StaticCell<
    [[[raw::lv_point_precise_t; ARROW_POINT_COUNT]; PAD_GRID_SIZE]; PAD_GRID_SIZE],
> = StaticCell::new();
static PAD_CELL_STYLE: StaticCell<raw::lv_style_t> = StaticCell::new();
static PAD_CELL_PRESSED_STYLE: StaticCell<raw::lv_style_t> = StaticCell::new();
static ARROW_LINE_STYLE: StaticCell<raw::lv_style_t> = StaticCell::new();

unsafe extern "C" fn on_publish_tick(_timer: *mut raw::lv_timer_t) {
    publish_command(*HELD_COMMAND.lock().unwrap());
}

unsafe extern "C" fn on_pad_event(event: *mut raw::lv_event_t) {
    if unsafe { raw::lv_event_get_target(event) }
        == unsafe { raw::lv_event_get_current_target(event) }
    {
        return;
    }
    let publish_timer =
        unsafe { raw::lv_event_get_user_data(event) } as *mut raw::lv_timer_t;
    let button = unsafe { raw::lv_event_get_target(event) } as *const raw::lv_obj_t;
    let cell_index = unsafe { raw::lv_obj_get_index(button) } as usize;
    let cell = PAD_CELLS[cell_index / PAD_GRID_SIZE][cell_index % PAD_GRID_SIZE];

    if unsafe { raw::lv_event_get_code(event) }
        == raw::lv_event_code_t_LV_EVENT_PRESSED
    {
        let command = DriveCommand {
            linear_x: LINEAR_SPEED * cell.command.linear_x,
            angular_z: ANGULAR_SPEED * cell.command.angular_z,
        };
        *HELD_COMMAND.lock().unwrap() = command;
        publish_command(command);
        unsafe { raw::lv_timer_resume(publish_timer) };
    } else {
        unsafe { raw::lv_timer_pause(publish_timer) };
        *HELD_COMMAND.lock().unwrap() = DriveCommand::STOP;
        publish_command(DriveCommand::STOP);
    }
}

unsafe extern "C" fn on_status_refresh(timer: *mut raw::lv_timer_t) {
    static DISPLAYED_STATE: AtomicU32 = AtomicU32::new(u32::MAX);
    let state = link_state();
    if state as u32 == DISPLAYED_STATE.load(Ordering::Relaxed) {
        return;
    }
    DISPLAYED_STATE.store(state as u32, Ordering::Relaxed);

    let status_label = unsafe { raw::lv_timer_get_user_data(timer) } as *mut raw::lv_obj_t;
    unsafe {
        raw::lv_label_set_text(status_label, state.status_text().as_ptr() as *const c_char)
    };
}

fn build_pad() {
    let pad_cell_style = PAD_CELL_STYLE.init(Default::default());
    let pad_cell_pressed_style = PAD_CELL_PRESSED_STYLE.init(Default::default());
    let arrow_line_style = ARROW_LINE_STYLE.init(Default::default());
    let arrow_points = ARROW_POINTS.init(core::array::from_fn(|_| {
        core::array::from_fn(|_| core::array::from_fn(|_| Default::default()))
    }));

    unsafe {
        raw::lv_style_init(pad_cell_style);
        raw::lv_style_set_bg_color(pad_cell_style, raw::lv_color_hex(GRUVBOX_CELL));
        raw::lv_style_set_border_color(
            pad_cell_style,
            raw::lv_color_hex(GRUVBOX_CELL_BORDER),
        );
        raw::lv_style_set_border_width(pad_cell_style, 1);
        raw::lv_style_set_radius(pad_cell_style, CELL_RADIUS);
        raw::lv_style_init(pad_cell_pressed_style);
        raw::lv_style_set_bg_color(
            pad_cell_pressed_style,
            raw::lv_color_hex(GRUVBOX_CELL_PRESSED),
        );
        raw::lv_style_set_border_color(
            pad_cell_pressed_style,
            raw::lv_color_hex(GRUVBOX_CELL_PRESSED_BORDER),
        );
        raw::lv_style_init(arrow_line_style);
        raw::lv_style_set_line_color(arrow_line_style, raw::lv_color_hex(GRUVBOX_ARROW));
        raw::lv_style_set_line_width(arrow_line_style, ARROW_LINE_WIDTH);
        raw::lv_style_set_line_rounded(arrow_line_style, true);

        let screen = raw::lv_screen_active();
        raw::lv_obj_set_style_bg_color(screen, raw::lv_color_hex(GRUVBOX_BACKGROUND), 0);
        raw::lv_obj_remove_flag(screen, raw::lv_obj_flag_t_LV_OBJ_FLAG_SCROLLABLE);

        let status_label = raw::lv_label_create(screen);
        raw::lv_obj_align(
            status_label,
            raw::lv_align_t_LV_ALIGN_TOP_MID,
            0,
            STATUS_TOP_MARGIN,
        );
        raw::lv_obj_set_style_text_color(status_label, raw::lv_color_hex(GRUVBOX_STATUS), 0);
        raw::lv_label_set_text(status_label, c"".as_ptr());

        let pad = raw::lv_obj_create(screen);
        raw::lv_obj_set_size(pad, PAD_SIZE, PAD_SIZE);
        raw::lv_obj_align(pad, raw::lv_align_t_LV_ALIGN_BOTTOM_MID, 0, 0);
        raw::lv_obj_set_style_bg_opa(pad, OPA_TRANSPARENT, 0);
        raw::lv_obj_set_style_border_width(pad, 0, 0);
        raw::lv_obj_set_style_pad_all(pad, PAD_PADDING, 0);
        raw::lv_obj_set_style_pad_gap(pad, PAD_PADDING, 0);
        raw::lv_obj_set_grid_dsc_array(pad, COLUMN_TEMPLATE.as_ptr(), ROW_TEMPLATE.as_ptr());
        raw::lv_obj_remove_flag(pad, raw::lv_obj_flag_t_LV_OBJ_FLAG_SCROLLABLE);

        for row in 0..PAD_GRID_SIZE {
            for column in 0..PAD_GRID_SIZE {
                let button = raw::lv_button_create(pad);
                raw::lv_obj_set_grid_cell(
                    button,
                    raw::lv_grid_align_t_LV_GRID_ALIGN_STRETCH,
                    column as i32,
                    1,
                    raw::lv_grid_align_t_LV_GRID_ALIGN_STRETCH,
                    row as i32,
                    1,
                );
                raw::lv_obj_add_style(button, pad_cell_style, 0);
                raw::lv_obj_add_style(
                    button,
                    pad_cell_pressed_style,
                    raw::lv_state_t_LV_STATE_PRESSED as u32,
                );

                match PAD_CELLS[row][column].arrow_heading {
                    None => {
                        let stop_label = raw::lv_label_create(button);
                        raw::lv_label_set_text(
                            stop_label,
                            STOP_SYMBOL.as_ptr() as *const c_char,
                        );
                        raw::lv_obj_set_style_text_color(
                            stop_label,
                            raw::lv_color_hex(GRUVBOX_STOP),
                            0,
                        );
                        raw::lv_obj_center(stop_label);
                    }
                    Some(heading) => {
                        let points = &mut arrow_points[row][column];
                        for (point, (base_x, base_y)) in
                            points.iter_mut().zip(ARROW_OUTLINE)
                        {
                            let x = base_x * heading.cosine - base_y * heading.sine;
                            let y = base_x * heading.sine + base_y * heading.cosine;
                            point.x = ((ARROW_BOX_SIZE / 2) as f32 + x)
                                as raw::lv_value_precise_t;
                            point.y = ((ARROW_BOX_SIZE / 2) as f32 + y)
                                as raw::lv_value_precise_t;
                        }
                        let arrow = raw::lv_line_create(button);
                        raw::lv_obj_set_size(arrow, ARROW_BOX_SIZE, ARROW_BOX_SIZE);
                        raw::lv_obj_center(arrow);
                        raw::lv_line_set_points(
                            arrow,
                            points.as_ptr(),
                            ARROW_POINT_COUNT as u32,
                        );
                        raw::lv_obj_add_style(arrow, arrow_line_style, 0);
                        raw::lv_obj_remove_flag(
                            arrow,
                            raw::lv_obj_flag_t_LV_OBJ_FLAG_CLICKABLE,
                        );
                    }
                }

                raw::lv_obj_add_flag(
                    button,
                    raw::lv_obj_flag_t_LV_OBJ_FLAG_EVENT_BUBBLE
                        | raw::lv_obj_flag_t_LV_OBJ_FLAG_PRESS_LOCK,
                );
            }
        }

        let publish_timer =
            raw::lv_timer_create(Some(on_publish_tick), PUBLISH_PERIOD_MS, core::ptr::null_mut());
        raw::lv_timer_pause(publish_timer);

        for event_code in [
            raw::lv_event_code_t_LV_EVENT_PRESSED,
            raw::lv_event_code_t_LV_EVENT_RELEASED,
            raw::lv_event_code_t_LV_EVENT_PRESS_LOST,
        ] {
            raw::lv_obj_add_event_cb(
                pad,
                Some(on_pad_event),
                event_code,
                publish_timer as *mut c_void,
            );
        }

        raw::lv_timer_create(
            Some(on_status_refresh),
            STATUS_REFRESH_PERIOD_MS,
            status_label as *mut c_void,
        );
    }
}

pub fn ui_thread_body() {
    while !unsafe { raw::lv_is_initialized() } {
        sleep(Duration::millis(LVGL_INIT_POLL_PERIOD_MS));
    }

    build_pad();

    unsafe {
        raw::lv_timer_handler();
        raw::display_blanking_off(zephyr::devicetree::labels::sh8601::get_instance_raw());
    }

    loop {
        let sleep_milliseconds = unsafe { raw::lv_timer_handler() };
        sleep(Duration::millis(u64::from(sleep_milliseconds.clamp(5, 100))));
    }
}
