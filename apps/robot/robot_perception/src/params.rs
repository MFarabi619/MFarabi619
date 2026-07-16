use oxidros::{core::parameter::Parameters, prelude::*};

pub const DEFAULT_IMAGE_TOPIC: &str = "camera/image_raw/compressed";

pub fn f64_param(store: &Parameters, name: &str, default: f64) -> f64 {
    match store.get_parameter(name).map(|parameter| &parameter.value) {
        Some(Value::F64(value)) => *value,
        Some(Value::I64(value)) => *value as f64,
        _ => default,
    }
}

pub fn string_param(store: &Parameters, name: &str, default: &str) -> String {
    match store.get_parameter(name).map(|parameter| &parameter.value) {
        Some(Value::String(value)) => value.clone(),
        _ => default.to_string(),
    }
}
