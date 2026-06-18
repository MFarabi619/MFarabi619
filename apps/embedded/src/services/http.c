#include <zephyr/net/http/server.h>
#include <zephyr/net/http/service.h>

static uint16_t web_port = 80;

static struct http_resource_detail_static_fs web_root_detail = {
	.common = {
		.type = HTTP_RESOURCE_TYPE_STATIC_FS,
		.bitmask_of_supported_http_methods = BIT(HTTP_GET),
	},
	.fs_path = "/SD:/www",
};

HTTP_SERVICE_DEFINE(web_service, NULL, &web_port, 3, 4, NULL, NULL, NULL);
HTTP_RESOURCE_DEFINE(web_root, web_service, "/*", &web_root_detail);
