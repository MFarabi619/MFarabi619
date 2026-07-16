use oxidros::{core::parameter::Parameters, prelude::*};

pub fn f64_param(store: &Parameters, name: &str, default: f64) -> f64 {
    match store.get_parameter(name).map(|parameter| &parameter.value) {
        Some(Value::F64(value)) => *value,
        Some(Value::I64(value)) => *value as f64,
        _ => default,
    }
}

pub fn bool_param(store: &Parameters, name: &str, default: bool) -> bool {
    match store.get_parameter(name).map(|parameter| &parameter.value) {
        Some(Value::Bool(value)) => *value,
        _ => default,
    }
}

pub fn string_param(store: &Parameters, name: &str, default: &str) -> String {
    match store.get_parameter(name).map(|parameter| &parameter.value) {
        Some(Value::String(value)) => value.clone(),
        _ => default.to_string(),
    }
}
