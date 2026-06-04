use core::ffi::{c_char, CStr};
use core::net::Ipv4Addr;

use crate::utils::errno::{Errno, IntoResult};

const DNS_RR_TYPE_A: u16 = 1;

#[repr(C)]
pub enum Decision {
    Answer = 0,
    Block = 1,
    Empty = 2,
    Forward = 3,
}

struct StaticHost {
    name: &'static [u8],
    addr: Ipv4Addr,
}

/* Anycast-only. Never add geo-DNS CDNs — clients hitting our stale snapshot
 * would land on a server far from their location.
 */
const STATIC_HOSTS: &[StaticHost] = &[
    StaticHost { name: b"one.one.one.one",               addr: Ipv4Addr::new(1, 1, 1, 1) },
    StaticHost { name: b"dns.google",                    addr: Ipv4Addr::new(8, 8, 8, 8) },
    StaticHost { name: b"dns.quad9.net",                 addr: Ipv4Addr::new(9, 9, 9, 9) },
    StaticHost { name: b"dns.opendns.com",               addr: Ipv4Addr::new(208, 67, 222, 222) },
    StaticHost { name: b"connectivitycheck.gstatic.com", addr: Ipv4Addr::new(142, 250, 80, 3) },
    StaticHost { name: b"connectivity-check.ubuntu.com", addr: Ipv4Addr::new(91, 189, 91, 49) },
    StaticHost { name: b"captive.apple.com",             addr: Ipv4Addr::new(17, 253, 144, 13) },
    StaticHost { name: b"time.google.com",               addr: Ipv4Addr::new(216, 239, 35, 4) },
    StaticHost { name: b"time.cloudflare.com",           addr: Ipv4Addr::new(162, 159, 200, 1) },
    StaticHost { name: b"time.facebook.com",             addr: Ipv4Addr::new(129, 134, 30, 123) },
];

/* Suffix-matched. Never include connectivitycheck.gstatic.com (captive-portal
 * probe target).
 */
const BLOCKLIST: &[&[u8]] = &[
    b".doubleclick.net",
    b".googleadservices.com",
    b".googlesyndication.com",
    b".google-analytics.com",
    b".googletagmanager.com",
    b".googletagservices.com",
    b"mtalk.google.com",
    b"alt1-mtalk.google.com",
    b"alt2-mtalk.google.com",
    b"alt3-mtalk.google.com",
    b"alt4-mtalk.google.com",
    b"alt5-mtalk.google.com",
    b"alt6-mtalk.google.com",
    b"alt7-mtalk.google.com",
    b"alt8-mtalk.google.com",
    b"androidwearcloudsync-pa.googleapis.com",
    b"nearbysharing-pa.googleapis.com",
    b"play.googleapis.com",
    b"play-fe.googleapis.com",
    b"semanticlocation-pa.googleapis.com",
    b"firebaseremoteconfig.googleapis.com",
    b"firebaseinstallations.googleapis.com",
    b".crashlytics.com",
    b".facebook.com",
    b".fbcdn.net",
    b".graph.facebook.com",
    b".instagram.com",
    b".twitter.com",
    b".tiktok.com",
    b".samsungdm.com",
    b".samsungcloud.com",
    b".samsungapps.com",
    b"bifrost.vivaldi.com",
    b".braze.com",
    b".branch.io",
    b".segment.io",
    b".mixpanel.com",
    b".amplitude.com",
    b".hotjar.com",
    b".doubleverify.com",
    b".scorecardresearch.com",
    b".quantserve.com",
    b".mopub.com",
    b".chartboost.com",
    b".applovin.com",
    b".unityads.unity3d.com",
    b"vortex.data.microsoft.com",
    b"telemetry.microsoft.com",
];

#[no_mangle]
pub unsafe extern "C" fn dnsDecide(
    name: *const c_char,
    qtype: u16,
    out_ip_be: *mut u32,
) -> Decision {
    let name = CStr::from_ptr(name).to_bytes();
    if name.is_empty() {
        return Decision::Forward;
    }

    if qtype == DNS_RR_TYPE_A {
        if let Some(h) = STATIC_HOSTS
            .iter()
            .find(|h| name.eq_ignore_ascii_case(h.name))
        {
            *out_ip_be = u32::from(h.addr).to_be();
            return Decision::Answer;
        }
    }

    if isBlocked(name) {
        return Decision::Block;
    }

    if qtype != DNS_RR_TYPE_A {
        return Decision::Empty;
    }

    Decision::Forward
}

fn isBlocked(qname: &[u8]) -> bool {
    BLOCKLIST.iter().any(|suffix| {
        qname.len() >= suffix.len()
            && qname[qname.len() - suffix.len()..].eq_ignore_ascii_case(suffix)
    })
}

pub fn initialize() -> Result<(), Errno> {
    unsafe { dnsProxyInitialize() }.ok()
}

extern "C" {
    fn dnsProxyInitialize() -> i32;
}
