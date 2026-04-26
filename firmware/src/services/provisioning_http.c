#include <zephyr/net/http/server.h>
#include <zephyr/net/http/service.h>

extern int provisioning_index_handler(struct http_client_ctx *client,
				      enum http_transaction_status status,
				      const struct http_request_ctx *request_ctx,
				      struct http_response_ctx *response_ctx,
				      void *user_data);

extern int provisioning_status_handler(struct http_client_ctx *client,
				       enum http_transaction_status status,
				       const struct http_request_ctx *request_ctx,
				       struct http_response_ctx *response_ctx,
				       void *user_data);

extern int provisioning_scan_handler(struct http_client_ctx *client,
				     enum http_transaction_status status,
				     const struct http_request_ctx *request_ctx,
				     struct http_response_ctx *response_ctx,
				     void *user_data);

extern int provisioning_connect_handler(struct http_client_ctx *client,
					enum http_transaction_status status,
					const struct http_request_ctx *request_ctx,
					struct http_response_ctx *response_ctx,
					void *user_data);

extern int provisioning_credentials_handler(struct http_client_ctx *client,
					    enum http_transaction_status status,
					    const struct http_request_ctx *request_ctx,
					    struct http_response_ctx *response_ctx,
					    void *user_data);

static uint16_t provisioning_port = 80;

HTTP_SERVICE_DEFINE(provisioning_service, "192.168.4.1", &provisioning_port, 2, 5, NULL, NULL, NULL);

static struct http_resource_detail_dynamic index_detail = {
	.common = {
		.type = HTTP_RESOURCE_TYPE_DYNAMIC,
		.bitmask_of_supported_http_methods = BIT(HTTP_GET),
	},
	.cb = provisioning_index_handler,
	.user_data = NULL,
};

static struct http_resource_detail_dynamic status_detail = {
	.common = {
		.type = HTTP_RESOURCE_TYPE_DYNAMIC,
		.bitmask_of_supported_http_methods = BIT(HTTP_GET),
	},
	.cb = provisioning_status_handler,
	.user_data = NULL,
};

static struct http_resource_detail_dynamic scan_detail = {
	.common = {
		.type = HTTP_RESOURCE_TYPE_DYNAMIC,
		.bitmask_of_supported_http_methods = BIT(HTTP_POST),
	},
	.cb = provisioning_scan_handler,
	.user_data = NULL,
};

static struct http_resource_detail_dynamic connect_detail = {
	.common = {
		.type = HTTP_RESOURCE_TYPE_DYNAMIC,
		.bitmask_of_supported_http_methods = BIT(HTTP_POST),
	},
	.cb = provisioning_connect_handler,
	.user_data = NULL,
};

static struct http_resource_detail_dynamic credentials_detail = {
	.common = {
		.type = HTTP_RESOURCE_TYPE_DYNAMIC,
		.bitmask_of_supported_http_methods = BIT(HTTP_DELETE),
	},
	.cb = provisioning_credentials_handler,
	.user_data = NULL,
};

HTTP_RESOURCE_DEFINE(provisioning_index, provisioning_service,
		     "/", &index_detail);
HTTP_RESOURCE_DEFINE(provisioning_status, provisioning_service,
		     "/api/wifi/status", &status_detail);
HTTP_RESOURCE_DEFINE(provisioning_scan, provisioning_service,
		     "/api/wifi/scan", &scan_detail);
HTTP_RESOURCE_DEFINE(provisioning_connect, provisioning_service,
		     "/api/wifi/connect", &connect_detail);
HTTP_RESOURCE_DEFINE(provisioning_credentials, provisioning_service,
		     "/api/wifi/credentials", &credentials_detail);
