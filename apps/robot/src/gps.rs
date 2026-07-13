use std::{sync::Arc, time::Duration};

use oxidros::{
    msg::{
        common_interfaces::sensor_msgs::msg::{NavSatFix, NavSatStatus},
        msg::RosString,
    },
    prelude::*,
};
use tokio::time::interval;

use crate::{frames::BASE_LINK, now_stamp, qos};

const LATITUDE_ORIGIN: f64 = 45.4215;
const LONGITUDE_ORIGIN: f64 = -75.6972;
const PUBLISH_HZ: f64 = 1.0;

fn placeholder_fix() -> NavSatFix {
    let (sec, nanosec) = now_stamp();
    let mut fix = NavSatFix::new().unwrap();
    fix.header.stamp.sec = sec;
    fix.header.stamp.nanosec = nanosec;
    fix.header.frame_id = RosString::new(BASE_LINK).unwrap();
    fix.status.status = NavSatStatus::STATUS_FIX;
    fix.status.service = NavSatStatus::SERVICE_GPS;
    fix.latitude = LATITUDE_ORIGIN;
    fix.longitude = LONGITUDE_ORIGIN;
    fix.altitude = 0.0;
    fix.position_covariance = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 4.0];
    fix.position_covariance_type = NavSatFix::COVARIANCE_TYPE_DIAGONAL_KNOWN;
    fix
}

pub async fn run_gps(node: Arc<Node>) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let publisher = node.create_publisher::<NavSatFix>("gps/fix", Some(qos::sensor_data()))?;
    tracing::warn!("publishing placeholder gps/fix at origin; wire real hardware later");
    let mut tick = interval(Duration::from_secs_f64(1.0 / PUBLISH_HZ));
    loop {
        tick.tick().await;
        publisher.send(&placeholder_fix())?;
    }
}

pub const EARTH_RADIUS_METERS: f64 = 6_378_137.0;

pub fn enu_to_geodetic(east: f64, north: f64, lat0: f64, lon0: f64) -> (f64, f64) {
    let latitude = lat0 + (north / EARTH_RADIUS_METERS).to_degrees();
    let longitude = lon0 + (east / (EARTH_RADIUS_METERS * lat0.to_radians().cos())).to_degrees();
    (latitude, longitude)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enu_origin_maps_to_origin() {
        let (lat, lon) = enu_to_geodetic(0.0, 0.0, 45.4215, -75.6972);
        assert_eq!(lat, 45.4215);
        assert_eq!(lon, -75.6972);
    }

    #[test]
    fn enu_moving_north_raises_latitude_only() {
        let (lat, lon) = enu_to_geodetic(0.0, 100.0, 45.4215, -75.6972);
        assert!(lat > 45.4215);
        assert_eq!(lon, -75.6972);
    }
}
