use core::ffi::c_int;

#[derive(Debug)]
pub enum MqttError {
    NotConnected,
    InvalidConfig,
    HostUnreachable,
    Transport(c_int),
}

fn from_result(code: c_int) -> Result<(), MqttError> {
    match code {
        0 => Ok(()),
        x if x == -(zephyr::raw::ENOTCONN as i32) => Err(MqttError::NotConnected),
        x if x == -(zephyr::raw::EINVAL as i32) => Err(MqttError::InvalidConfig),
        x if x == -(zephyr::raw::EHOSTUNREACH as i32) => Err(MqttError::HostUnreachable),
        other => Err(MqttError::Transport(other)),
    }
}

const MAX_INCOMING_TOPIC_LENGTH: usize = 128;
const MAX_INCOMING_PAYLOAD_LENGTH: usize = 128;

unsafe extern "C" {
    fn mqtt_service_init() -> c_int;
    fn mqtt_service_is_configured() -> bool;
    fn mqtt_service_is_connected() -> bool;
    fn mqtt_service_connect() -> c_int;
    fn mqtt_service_publish(
        topic: *const u8,
        payload: *const u8,
        payload_length: usize,
        retain: bool,
    ) -> c_int;
    fn mqtt_service_disconnect() -> c_int;
    fn mqtt_service_poll(timeout_milliseconds: c_int) -> c_int;
    fn mqtt_service_keepalive_time_left() -> c_int;
    fn mqtt_service_get_incoming(
        topic_out: *mut u8,
        topic_length: *mut usize,
        payload_out: *mut u8,
        payload_length: *mut usize,
    ) -> c_int;
    fn mqtt_service_set_config(
        host: *const u8,
        port: u16,
        username: *const u8,
        password: *const u8,
    ) -> c_int;
    fn mqtt_service_get_publish_interval() -> u32;
    fn mqtt_service_set_publish_interval(seconds: u32);
    fn mqtt_service_get_deep_sleep_enabled() -> bool;
    fn mqtt_service_set_deep_sleep_enabled(enabled: bool);
    fn mqtt_service_get_sleep_duration() -> u32;
    fn mqtt_service_set_sleep_duration(seconds: u32);
    fn mqtt_service_get_host() -> *const u8;
    fn mqtt_service_get_port() -> u16;
    fn mqtt_service_get_username() -> *const u8;
    fn mqtt_service_get_availability_topic() -> *const u8;
}

pub fn init() -> Result<(), MqttError> {
    from_result(unsafe { mqtt_service_init() })
}

pub fn is_configured() -> bool {
    unsafe { mqtt_service_is_configured() }
}

pub fn is_connected() -> bool {
    unsafe { mqtt_service_is_connected() }
}

pub fn connect() -> Result<(), MqttError> {
    from_result(unsafe { mqtt_service_connect() })
}

pub fn publish(topic: &str, payload: &[u8], retain: bool) -> Result<(), MqttError> {
    let topic_cstr = make_c_string::<128>(topic);
    from_result(unsafe {
        mqtt_service_publish(topic_cstr.as_ptr(), payload.as_ptr(), payload.len(), retain)
    })
}

pub fn disconnect() -> Result<(), MqttError> {
    from_result(unsafe { mqtt_service_disconnect() })
}

pub fn poll(timeout_milliseconds: i32) -> Result<(), MqttError> {
    from_result(unsafe { mqtt_service_poll(timeout_milliseconds) })
}

pub fn keepalive_time_left() -> i32 {
    unsafe { mqtt_service_keepalive_time_left() }
}

static mut INCOMING_TOPIC: [u8; MAX_INCOMING_TOPIC_LENGTH] = [0; MAX_INCOMING_TOPIC_LENGTH];
static mut INCOMING_PAYLOAD: [u8; MAX_INCOMING_PAYLOAD_LENGTH] = [0; MAX_INCOMING_PAYLOAD_LENGTH];

pub fn get_incoming_command() -> Option<(&'static str, &'static [u8])> {
    use core::ptr::addr_of_mut;

    unsafe {
        let mut topic_length: usize = 0;
        let mut payload_length: usize = 0;

        let topic_ptr = addr_of_mut!(INCOMING_TOPIC) as *mut u8;
        let payload_ptr = addr_of_mut!(INCOMING_PAYLOAD) as *mut u8;

        let result = mqtt_service_get_incoming(
            topic_ptr,
            &mut topic_length,
            payload_ptr,
            &mut payload_length,
        );

        if result != 0 {
            return None;
        }

        let topic = core::str::from_utf8(
            core::slice::from_raw_parts(topic_ptr, topic_length),
        ).ok()?;
        let payload = core::slice::from_raw_parts(payload_ptr, payload_length);
        Some((topic, payload))
    }
}

pub fn publish_interval() -> u32 {
    unsafe { mqtt_service_get_publish_interval() }
}

pub fn set_publish_interval(seconds: u32) {
    unsafe { mqtt_service_set_publish_interval(seconds) }
}

pub fn deep_sleep_enabled() -> bool {
    unsafe { mqtt_service_get_deep_sleep_enabled() }
}

pub fn set_deep_sleep_enabled(enabled: bool) {
    unsafe { mqtt_service_set_deep_sleep_enabled(enabled) }
}

pub fn sleep_duration() -> u32 {
    unsafe { mqtt_service_get_sleep_duration() }
}

pub fn set_sleep_duration(seconds: u32) {
    unsafe { mqtt_service_set_sleep_duration(seconds) }
}

pub fn set_config(host: &str, port: u16, username: Option<&str>, password: Option<&str>) -> Result<(), MqttError> {
    let host_cstr = make_c_string::<64>(host);
    let username_cstr = username.map(make_c_string::<64>);
    let password_cstr = password.map(make_c_string::<64>);

    let username_ptr = username_cstr.as_ref().map_or(core::ptr::null(), |s| s.as_ptr());
    let password_ptr = password_cstr.as_ref().map_or(core::ptr::null(), |s| s.as_ptr());

    from_result(unsafe {
        mqtt_service_set_config(host_cstr.as_ptr(), port, username_ptr, password_ptr)
    })
}

fn make_c_string<const N: usize>(source: &str) -> [u8; N] {
    let mut buffer = [0u8; N];
    let length = source.len().min(N - 1);
    buffer[..length].copy_from_slice(&source.as_bytes()[..length]);
    buffer
}
