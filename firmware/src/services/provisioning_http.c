#include <zephyr/net/http/server.h>
#include <zephyr/net/http/service.h>

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

HTTP_SERVICE_DEFINE(provisioning_service, "0.0.0.0", &provisioning_port, 2, 5, NULL, NULL, NULL);

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

HTTP_RESOURCE_DEFINE(provisioning_status, provisioning_service,
		     "/api/wifi/status", &status_detail);
HTTP_RESOURCE_DEFINE(provisioning_scan, provisioning_service,
		     "/api/wifi/scan", &scan_detail);
HTTP_RESOURCE_DEFINE(provisioning_connect, provisioning_service,
		     "/api/wifi/connect", &connect_detail);
HTTP_RESOURCE_DEFINE(provisioning_credentials, provisioning_service,
		     "/api/wifi/credentials", &credentials_detail);

extern int device_status_handler(struct http_client_ctx *client,
				 enum http_transaction_status status,
				 const struct http_request_ctx *request_ctx,
				 struct http_response_ctx *response_ctx,
				 void *user_data);

extern int cloudevents_handler(struct http_client_ctx *client,
			       enum http_transaction_status status,
			       const struct http_request_ctx *request_ctx,
			       struct http_response_ctx *response_ctx,
			       void *user_data);

extern int filesystem_dispatch_handler(struct http_client_ctx *client,
				       enum http_transaction_status status,
				       const struct http_request_ctx *request_ctx,
				       struct http_response_ctx *response_ctx,
				       void *user_data);

static struct http_resource_detail_dynamic filesystem_detail = {
	.common = {
		.type = HTTP_RESOURCE_TYPE_DYNAMIC,
		.bitmask_of_supported_http_methods = BIT(HTTP_GET) | BIT(HTTP_PUT) | BIT(HTTP_DELETE) | BIT(HTTP_POST) | BIT(HTTP_PATCH),
	},
	.cb = filesystem_dispatch_handler,
	.user_data = NULL,
};

HTTP_RESOURCE_DEFINE(filesystem, provisioning_service,
		     "/api/filesystem/*", &filesystem_detail);

static struct http_resource_detail_static_fs static_files_detail = {
	.common = {
		.type = HTTP_RESOURCE_TYPE_STATIC_FS,
		.bitmask_of_supported_http_methods = BIT(HTTP_GET),
	},
	.fs_path = "/sd:/public",
};

HTTP_RESOURCE_DEFINE(zzz_static_files, provisioning_service,
		     "/*", &static_files_detail);

static struct http_resource_detail_dynamic device_status_detail = {
	.common = {
		.type = HTTP_RESOURCE_TYPE_DYNAMIC,
		.bitmask_of_supported_http_methods = BIT(HTTP_GET),
	},
	.cb = device_status_handler,
	.user_data = NULL,
};

HTTP_RESOURCE_DEFINE(device_status, provisioning_service,
		     "/api/system/device/status", &device_status_detail);

static struct http_resource_detail_dynamic cloudevents_detail = {
	.common = {
		.type = HTTP_RESOURCE_TYPE_DYNAMIC,
		.bitmask_of_supported_http_methods = BIT(HTTP_GET),
	},
	.cb = cloudevents_handler,
	.user_data = NULL,
};

HTTP_RESOURCE_DEFINE(cloudevents, provisioning_service,
		     "/api/cloudevents", &cloudevents_detail);

extern int wind_speed_handler(struct http_client_ctx *client,
			      enum http_transaction_status status,
			      const struct http_request_ctx *request_ctx,
			      struct http_response_ctx *response_ctx,
			      void *user_data);

extern int wind_direction_handler(struct http_client_ctx *client,
				  enum http_transaction_status status,
				  const struct http_request_ctx *request_ctx,
				  struct http_response_ctx *response_ctx,
				  void *user_data);

extern int rainfall_handler(struct http_client_ctx *client,
			    enum http_transaction_status status,
			    const struct http_request_ctx *request_ctx,
			    struct http_response_ctx *response_ctx,
			    void *user_data);

extern int soil_handler(struct http_client_ctx *client,
			enum http_transaction_status status,
			const struct http_request_ctx *request_ctx,
			struct http_response_ctx *response_ctx,
			void *user_data);

static struct http_resource_detail_dynamic wind_speed_detail = {
	.common = {
		.type = HTTP_RESOURCE_TYPE_DYNAMIC,
		.bitmask_of_supported_http_methods = BIT(HTTP_GET),
	},
	.cb = wind_speed_handler,
	.user_data = NULL,
};

HTTP_RESOURCE_DEFINE(wind_speed, provisioning_service,
		     "/api/sensors/wind/speed", &wind_speed_detail);

static struct http_resource_detail_dynamic wind_direction_detail = {
	.common = {
		.type = HTTP_RESOURCE_TYPE_DYNAMIC,
		.bitmask_of_supported_http_methods = BIT(HTTP_GET),
	},
	.cb = wind_direction_handler,
	.user_data = NULL,
};

HTTP_RESOURCE_DEFINE(wind_direction, provisioning_service,
		     "/api/sensors/wind/direction", &wind_direction_detail);

static struct http_resource_detail_dynamic rainfall_detail = {
	.common = {
		.type = HTTP_RESOURCE_TYPE_DYNAMIC,
		.bitmask_of_supported_http_methods = BIT(HTTP_GET),
	},
	.cb = rainfall_handler,
	.user_data = NULL,
};

HTTP_RESOURCE_DEFINE(rainfall, provisioning_service,
		     "/api/sensors/rainfall", &rainfall_detail);

static struct http_resource_detail_dynamic soil_detail = {
	.common = {
		.type = HTTP_RESOURCE_TYPE_DYNAMIC,
		.bitmask_of_supported_http_methods = BIT(HTTP_GET),
	},
	.cb = soil_handler,
	.user_data = NULL,
};

HTTP_RESOURCE_DEFINE(soil, provisioning_service,
		     "/api/sensors/soil", &soil_detail);

extern int reboot_handler(struct http_client_ctx *client,
			  enum http_transaction_status status,
			  const struct http_request_ctx *request_ctx,
			  struct http_response_ctx *response_ctx,
			  void *user_data);

static struct http_resource_detail_dynamic reboot_detail = {
	.common = {
		.type = HTTP_RESOURCE_TYPE_DYNAMIC,
		.bitmask_of_supported_http_methods = BIT(HTTP_POST),
	},
	.cb = reboot_handler,
	.user_data = NULL,
};

HTTP_RESOURCE_DEFINE(device_reboot, provisioning_service,
		     "/api/system/device/actions/reset", &reboot_detail);
