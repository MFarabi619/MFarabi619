use core::ffi::c_int;

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

pub fn init() -> Result<(), c_int> {
    let result = unsafe { mqtt_service_init() };
    if result == 0 { Ok(()) } else { Err(result) }
}

pub fn is_configured() -> bool {
    unsafe { mqtt_service_is_configured() }
}

pub fn is_connected() -> bool {
    unsafe { mqtt_service_is_connected() }
}

pub fn connect() -> Result<(), c_int> {
    let result = unsafe { mqtt_service_connect() };
    if result == 0 { Ok(()) } else { Err(result) }
}

pub fn publish(topic: &str, payload: &[u8], retain: bool) -> Result<(), c_int> {
    let topic_cstr = make_c_string::<128>(topic);
    let result = unsafe {
        mqtt_service_publish(topic_cstr.as_ptr(), payload.as_ptr(), payload.len(), retain)
    };
    if result == 0 { Ok(()) } else { Err(result) }
}

pub fn disconnect() -> Result<(), c_int> {
    let result = unsafe { mqtt_service_disconnect() };
    if result == 0 { Ok(()) } else { Err(result) }
}

pub fn poll(timeout_milliseconds: i32) -> Result<(), c_int> {
    let result = unsafe { mqtt_service_poll(timeout_milliseconds) };
    if result == 0 { Ok(()) } else { Err(result) }
}

pub fn keepalive_time_left() -> i32 {
    unsafe { mqtt_service_keepalive_time_left() }
}

static mut INCOMING_TOPIC: [u8; 128] = [0; 128];
static mut INCOMING_PAYLOAD: [u8; 128] = [0; 128];

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

        let topic = core::str::from_utf8_unchecked(
            core::slice::from_raw_parts(topic_ptr, topic_length),
        );
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

pub fn set_config(host: &str, port: u16, username: Option<&str>, password: Option<&str>) -> Result<(), c_int> {
    let host_cstr = make_c_string::<64>(host);
    let username_cstr = username.map(make_c_string::<64>);
    let password_cstr = password.map(make_c_string::<64>);

    let username_ptr = username_cstr.as_ref().map_or(core::ptr::null(), |s| s.as_ptr());
    let password_ptr = password_cstr.as_ref().map_or(core::ptr::null(), |s| s.as_ptr());

    let result = unsafe {
        mqtt_service_set_config(host_cstr.as_ptr(), port, username_ptr, password_ptr)
    };
    if result == 0 { Ok(()) } else { Err(result) }
}

fn make_c_string<const N: usize>(source: &str) -> [u8; N] {
    let mut buffer = [0u8; N];
    let length = source.len().min(N - 1);
    buffer[..length].copy_from_slice(&source.as_bytes()[..length]);
    buffer
}
