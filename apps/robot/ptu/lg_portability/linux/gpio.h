/* lg's headers transitively #include <linux/gpio.h>, but the remote-client
 * sources we compile (rgpio, lgCfg, lgErr, lgDbg, lgMD5) reference no symbols
 * from it. This empty stub lets librgpio build on non-Linux hosts (e.g. macOS);
 * the real header is only needed by lg's local GPIO backend, which we don't build. */
