#pragma once

class AsyncWebServer;
class AsyncRateLimitMiddleware;

namespace services::http::api {

  namespace database {
    void registerRoutes(AsyncWebServer &server);
#ifdef PIO_UNIT_TESTING
    void test();
#endif
  }

  namespace email {
    void registerRoutes(AsyncWebServer &server);
  }

  namespace filesystem {
    void registerRoutes(AsyncWebServer &server,
                        AsyncRateLimitMiddleware &format_limit);
  }

  namespace networking {
    void registerRoutes(AsyncWebServer &server,
                        AsyncRateLimitMiddleware &scan_limit);
  }

  namespace sensors {
    void registerRoutes(AsyncWebServer &server);
  }

  namespace system {
    void registerRoutes(AsyncWebServer &server,
                        AsyncRateLimitMiddleware &reset_limit,
                        AsyncRateLimitMiddleware &ota_limit);
  }

}
