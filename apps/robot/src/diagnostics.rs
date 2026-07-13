use oxidros::msg::{
    common_interfaces::diagnostic_msgs::msg::{
        DiagnosticArray, DiagnosticStatus, DiagnosticStatusSeq, KeyValue, KeyValueSeq,
    },
    msg::RosString,
};

use crate::now_stamp;

const BATTERY_CRITICAL_PERCENT: f64 = 10.0;
const BATTERY_WARN_PERCENT: f64 = 30.0;

pub fn battery_diagnostic_level(percent: f64) -> u8 {
    if percent < BATTERY_CRITICAL_PERCENT {
        DiagnosticStatus::ERROR
    } else if percent < BATTERY_WARN_PERCENT {
        DiagnosticStatus::WARN
    } else {
        DiagnosticStatus::OK
    }
}

pub struct Status {
    inner: DiagnosticStatus,
    values: Vec<KeyValue>,
}

impl Status {
    pub fn new(level: u8, name: &str, hardware_id: &str) -> Self {
        let mut inner = DiagnosticStatus::new().unwrap();
        inner.level = level;
        inner.name = RosString::new(name).unwrap();
        inner.hardware_id = RosString::new(hardware_id).unwrap();
        Self {
            inner,
            values: Vec::new(),
        }
    }

    pub fn message(mut self, message: &str) -> Self {
        self.inner.message = RosString::new(message).unwrap();
        self
    }

    pub fn value(mut self, key: &str, value: &str) -> Self {
        let mut entry = KeyValue::new().unwrap();
        entry.key = RosString::new(key).unwrap();
        entry.value = RosString::new(value).unwrap();
        self.values.push(entry);
        self
    }

    fn build(self) -> DiagnosticStatus {
        let mut status = self.inner;
        status.values = KeyValueSeq::<0>::from_vec(self.values).unwrap();
        status
    }
}

pub fn diagnostic_array(statuses: Vec<Status>) -> DiagnosticArray {
    let (sec, nanosec) = now_stamp();
    let mut array = DiagnosticArray::new().unwrap();
    array.header.stamp.sec = sec;
    array.header.stamp.nanosec = nanosec;
    array.status =
        DiagnosticStatusSeq::<0>::from_vec(statuses.into_iter().map(Status::build).collect())
            .unwrap();
    array
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn battery_full_is_ok() {
        assert_eq!(battery_diagnostic_level(80.0), DiagnosticStatus::OK);
    }

    #[test]
    fn battery_low_warns() {
        assert_eq!(battery_diagnostic_level(20.0), DiagnosticStatus::WARN);
    }

    #[test]
    fn battery_critical_errors() {
        assert_eq!(battery_diagnostic_level(5.0), DiagnosticStatus::ERROR);
    }
}
