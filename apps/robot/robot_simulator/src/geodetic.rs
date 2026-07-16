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
