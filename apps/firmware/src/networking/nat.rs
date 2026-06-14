use zephyr::raw::{
    net_if_get_by_iface, net_if_get_wifi_sap, net_ip_protocol_NET_IPPROTO_ICMP,
    net_ip_protocol_NET_IPPROTO_TCP, net_ip_protocol_NET_IPPROTO_UDP, net_iptable_rule_params,
    net_ipv4_table_rule_add,
};

use zephyr::error::to_result_void;

use crate::networking::cellular::cellular_ppp_iface;

const ENODEV: i32 = -19;

struct ProtocolTimeouts {
    proto: u32,
    unreply_s: i32,
    reply_s: i32,
}

const PROTOCOLS: [ProtocolTimeouts; 3] = [
    ProtocolTimeouts { proto: net_ip_protocol_NET_IPPROTO_TCP,  unreply_s: 30, reply_s: 300 },
    ProtocolTimeouts { proto: net_ip_protocol_NET_IPPROTO_UDP,  unreply_s: 30, reply_s: 120 },
    ProtocolTimeouts { proto: net_ip_protocol_NET_IPPROTO_ICMP, unreply_s: 15, reply_s: 120 },
];

pub fn initialize() -> zephyr::Result<()> {
    let access_point_iface = unsafe { net_if_get_wifi_sap() };
    let cellular_iface = cellular_ppp_iface();
    if access_point_iface.is_null() || cellular_iface.is_null() {
        return to_result_void(ENODEV);
    }
    let access_point_idx = unsafe { net_if_get_by_iface(access_point_iface) };
    let cellular_idx = unsafe { net_if_get_by_iface(cellular_iface) };

    for protocol in PROTOCOLS {
        let mut params: net_iptable_rule_params = unsafe { core::mem::zeroed() };
        params.input_iface_idx = access_point_idx;
        params.output_iface_idx = cellular_idx;
        params.proto = protocol.proto;
        params.unreply_timeout = protocol.unreply_s;
        params.reply_timeout = protocol.reply_s;
        to_result_void(unsafe { net_ipv4_table_rule_add(&mut params) })?;
    }
    Ok(())
}
