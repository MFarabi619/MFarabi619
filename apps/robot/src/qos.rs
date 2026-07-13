use oxidros::core::qos::{DurabilityPolicy, HistoryPolicy, Profile, ReliabilityPolicy};

pub fn sensor_data() -> Profile {
    Profile::sensor_data()
}

pub fn command() -> Profile {
    Profile {
        reliability: ReliabilityPolicy::BestEffort,
        history: HistoryPolicy::KeepLast,
        depth: 1,
        ..Default::default()
    }
}

pub fn transient_local() -> Profile {
    Profile {
        durability: DurabilityPolicy::TransientLocal,
        history: HistoryPolicy::KeepLast,
        depth: 1,
        ..Default::default()
    }
}

pub fn default_reliable() -> Profile {
    Profile::default()
}
