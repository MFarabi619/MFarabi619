#include <zephyr/net/net_if.h>

#if defined(CONFIG_NET_L2_PPP)
#include <zephyr/net/ppp.h>
struct net_if *get_ppp_iface(void) {
	return net_if_get_first_by_type(&NET_L2_GET_NAME(PPP));
}
#else
struct net_if *get_ppp_iface(void) {
	return NULL;
}
#endif

extern void rust_main(void);

int main(void)
{
	rust_main();
	return 0;
}
