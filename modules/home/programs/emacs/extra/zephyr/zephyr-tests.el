;;; zephyr-tests.el --- Buttercup tests for zephyr.el  -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:

(require 'buttercup)
(require 'ert-x)
(require 'zephyr)

(buttercup-define-matcher-for-binary-function
  :to-be-file-equal file-equal-p
  :expect-match-phrase    "Expected `%A' to refer to the same file as `%B', but it was `%a'."
  :expect-mismatch-phrase "Expected `%A' not to refer to the same file as `%B', but it did.")

(defun zephyr-tests--make-workspace-with-app (ws relative-app)
  "Create a .west workspace in WS with an app at RELATIVE-APP/zephyr/patches.yml.
Return the absolute app path."
  (make-directory (expand-file-name ".west" ws))
  (let* ((app    (expand-file-name (file-name-as-directory relative-app) ws))
          (zephyr (expand-file-name "zephyr" app)))
    (make-directory zephyr t)
    (write-region "" nil (expand-file-name "patches.yml" zephyr))
    app))

(describe "zephyr-app-p"
  (it "is non-nil with the canonical Zephyr boilerplate"
    (ert-with-temp-directory dir
      (write-region "find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})\nproject(firmware)"
        nil (expand-file-name "CMakeLists.txt" dir))
      (expect (zephyr-app-p dir))))

  (it "accepts the bare find_package(Zephyr) form"
    (ert-with-temp-directory dir
      (write-region "find_package(Zephyr)\nproject(x)"
        nil (expand-file-name "CMakeLists.txt" dir))
      (expect (zephyr-app-p dir))))

  (it "is case-insensitive on both calls"
    (ert-with-temp-directory dir
      (write-region "FIND_PACKAGE(Zephyr)\nPROJECT(x)"
        nil (expand-file-name "CMakeLists.txt" dir))
      (expect (zephyr-app-p dir))))

  (it "is nil when CMakeLists.txt is missing"
    (ert-with-temp-directory dir
      (expect (zephyr-app-p dir) :not :to-be-truthy)))

  (it "is nil when find_package(Zephyr) is present but project() is missing"
    (ert-with-temp-directory dir
      (write-region "find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})\n"
        nil (expand-file-name "CMakeLists.txt" dir))
      (expect (zephyr-app-p dir) :not :to-be-truthy)))

  (it "is nil when project() is present but find_package(Zephyr) is missing"
    (ert-with-temp-directory dir
      (write-region "project(plain_cmake)\nadd_executable(foo foo.c)"
        nil (expand-file-name "CMakeLists.txt" dir))
      (expect (zephyr-app-p dir) :not :to-be-truthy)))

  (it "is nil when only Sysbuild (not Zephyr) is required"
    (ert-with-temp-directory dir
      (write-region "find_package(Sysbuild REQUIRED HINTS $ENV{ZEPHYR_BASE})\nproject(x)"
        nil (expand-file-name "CMakeLists.txt" dir))
      (expect (zephyr-app-p dir) :not :to-be-truthy))))

(describe "zephyr-app-root"
  (it "walks up from a subdirectory to find the app root"
    (ert-with-temp-directory dir
      (write-region "find_package(Zephyr)\nproject(x)"
        nil (expand-file-name "CMakeLists.txt" dir))
      (let ((subdir (expand-file-name "src" dir)))
        (make-directory subdir)
        (let ((default-directory subdir))
          (expect (zephyr-app-root) :to-be-file-equal dir)))))

  (it "returns nil when no app is found in the parent chain"
    (ert-with-temp-directory dir
      (let ((default-directory dir))
        (expect (zephyr-app-root) :not :to-be-truthy)))))

(describe "zephyr-app-name"
  (it "extracts the project name from a Zephyr CMakeLists.txt"
    (ert-with-temp-directory dir
      (write-region "find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})\nproject(firmware)"
        nil (expand-file-name "CMakeLists.txt" dir))
      (expect (zephyr-app-name dir) :to-equal "firmware")))

  (it "is case-insensitive on the project() keyword"
    (ert-with-temp-directory dir
      (write-region "find_package(Zephyr)\nPROJECT(my_app)"
        nil (expand-file-name "CMakeLists.txt" dir))
      (expect (zephyr-app-name dir) :to-equal "my_app")))

  (it "returns nil when CMakeLists.txt has no project() call"
    (ert-with-temp-directory dir
      (write-region "find_package(Zephyr)\n" nil (expand-file-name "CMakeLists.txt" dir))
      (expect (zephyr-app-name dir) :not :to-be-truthy))))

(describe "zephyr-app-boards"
  :var (dir)
  (before-each
    (setq dir (make-temp-file "zephyr-test-" t))
    (let ((boards (expand-file-name "boards" dir)))
      (make-directory boards)
      (write-region "" nil (expand-file-name "walter_esp32s3_procpu.conf" boards))
      (write-region "" nil (expand-file-name "walter_esp32s3_procpu.overlay" boards))
      (write-region "" nil (expand-file-name "qemu_riscv32.conf" boards))
      (write-region "" nil (expand-file-name "xiao_esp32s3_esp32s3_procpu.conf" boards))
      (write-region "" nil (expand-file-name "README.md" boards))))
  (after-each (delete-directory dir t))

  (it "returns the deduped basenames of .conf and .overlay files under boards/"
    (expect (zephyr-app-boards dir)
      :to-have-same-items-as
      '("walter_esp32s3_procpu" "qemu_riscv32" "xiao_esp32s3_esp32s3_procpu")))

  (it "returns nil for an app with no boards/ directory"
    (ert-with-temp-directory empty
      (expect (zephyr-app-boards empty) :not :to-be-truthy))))

(describe "zephyr-base"
  (before-each
    (spy-on 'west-config :and-return-value nil))

  (it "honors ZEPHYR_BASE env var when set and prefer is the default (env)"
    (with-environment-variables (("ZEPHYR_BASE" "/explicit/zephyr"))
      (expect (zephyr-base) :to-equal "/explicit/zephyr/")))

  (it "falls back to zephyr.base from .west/config (relative, resolved against workspace)"
    (with-environment-variables (("ZEPHYR_BASE" nil))
      (spy-on 'west-config :and-return-value
        '(("zephyr.base" . "zephyrproject/zephyr")))
      (expect (zephyr-base "/some/ws/") :to-equal "/some/ws/zephyrproject/zephyr/")))

  (it "honors an absolute zephyr.base value as-is"
    (with-environment-variables (("ZEPHYR_BASE" nil))
      (spy-on 'west-config :and-return-value
        '(("zephyr.base" . "/abs/zephyr")))
      (expect (zephyr-base "/some/ws/") :to-equal "/abs/zephyr/")))

  (it "lets zephyr.base configfile win when zephyr.base-prefer is configfile"
    (with-environment-variables (("ZEPHYR_BASE" "/env/zephyr"))
      (spy-on 'west-config :and-return-value
        '(("zephyr.base"        . "/cfg/zephyr")
           ("zephyr.base-prefer" . "configfile")))
      (expect (zephyr-base "/some/ws/") :to-equal "/cfg/zephyr/")))

  (it "returns nil when neither env nor config provide a value"
    (with-environment-variables (("ZEPHYR_BASE" nil))
      (spy-on 'west-workspace-root :and-return-value nil)
      (expect (zephyr-base) :not :to-be-truthy))))

(describe "zephyr-version"
  (it "reads and trims the VERSION file"
    (ert-with-temp-directory dir
      (write-region "v1.5.0\n" nil (expand-file-name "VERSION" dir))
      (expect (zephyr-version dir) :to-equal "v1.5.0")))

  (it "returns nil when no VERSION file exists"
    (ert-with-temp-directory dir
      (expect (zephyr-version dir) :not :to-be-truthy))))

(describe "zephyr--cache-load and zephyr--cache-save"
  (it "round-trips a Lisp value through the disk cache"
    (ert-with-temp-directory dir
      (let ((zephyr-cache-dir dir)
             (data (list :version "v1.0" :data '((:id "a") (:id "b")))))
        (zephyr--cache-save "thing" data)
        (expect (zephyr--cache-load "thing") :to-equal data))))

  (it "returns nil when the cache file does not exist"
    (ert-with-temp-directory dir
      (let ((zephyr-cache-dir dir))
        (expect (zephyr--cache-load "missing") :not :to-be-truthy)))))

(describe "zephyr-boards"
  :var (base)
  (before-each
    (spy-on 'zephyr-apps :and-return-value nil)
    (setq base (file-name-as-directory (make-temp-file "zephyr-test-" t)))
    (make-directory (expand-file-name "boards/vendor1/board1" base) t)
    (make-directory (expand-file-name "boards/vendor1/board2" base) t)
    (write-region "identifier: board1/socA/core1\nname: Board One\narch: arm\nvendor: vendor1\n"
      nil (expand-file-name "boards/vendor1/board1/board1.yaml" base))
    (write-region "identifier: board2/socB/core1\nname: Board Two\narch: riscv\nvendor: vendor1\n"
      nil (expand-file-name "boards/vendor1/board2/board2.yaml" base))
    (write-region "foo: bar\n"
      nil (expand-file-name "boards/vendor1/board1/notes.yaml" base)))
  (after-each (delete-directory base t))

  (it "parses every board YAML under the boards/ tree"
    (expect (length (zephyr-boards base)) :to-equal 2))

  (it "also picks up boards contributed by Zephyr apps' boards/ dirs"
    (let ((app-dir (make-temp-file "zephyr-app-" t)))
      (unwind-protect
        (let ((app-boards (expand-file-name "boards/others/customboard" app-dir)))
          (make-directory app-boards t)
          (write-region "identifier: customboard/socC/core1\nname: Custom\narch: arm\nvendor: me\n"
            nil (expand-file-name "customboard_socC_core1.yaml" app-boards))
          (spy-on 'zephyr-apps :and-return-value (list (list :path app-dir)))
          (let ((ids (mapcar (lambda (b) (plist-get b :id)) (zephyr-boards base))))
            (expect ids :to-have-same-items-as
              '("board1/socA/core1"
                 "board2/socB/core1"
                 "customboard/socC/core1"))))
        (delete-directory app-dir t))))

  (it "exposes :id :name :arch :vendor for each board"
    (let* ((boards (zephyr-boards base))
            (by-id (sort boards (lambda (a b) (string< (plist-get a :id)
                                                (plist-get b :id))))))
      (expect (plist-get (nth 0 by-id) :id)     :to-equal "board1/socA/core1")
      (expect (plist-get (nth 0 by-id) :name)   :to-equal "Board One")
      (expect (plist-get (nth 0 by-id) :arch)   :to-equal "arm")
      (expect (plist-get (nth 0 by-id) :vendor) :to-equal "vendor1")
      (expect (plist-get (nth 1 by-id) :arch)   :to-equal "riscv")))

  (it "returns nil when no boards/ directory exists"
    (ert-with-temp-directory empty
      (expect (zephyr-boards empty) :not :to-be-truthy))))

(describe "zephyr-sdk-path"
  :var (dir sdk)
  (before-each
    (setq dir (make-temp-file "zephyr-test-" t))
    (setq sdk (expand-file-name "zephyr-sdk-1.5.0" dir))
    (make-directory sdk)
    (write-region "1.5.0" nil (expand-file-name "sdk_version" sdk)))
  (after-each (delete-directory dir t))

  (it "returns ZEPHYR_SDK_INSTALL_DIR when set"
    (with-environment-variables (("ZEPHYR_SDK_INSTALL_DIR" "/explicit/sdk"))
      (expect (zephyr-sdk-path) :to-equal "/explicit/sdk")))

  (it "discovers an SDK via search paths when the env var is unset"
    (with-environment-variables (("ZEPHYR_SDK_INSTALL_DIR" nil))
      (let ((zephyr-sdk-search-paths (list (concat dir "/zephyr-sdk-*"))))
        (expect (zephyr-sdk-path) :to-be-file-equal sdk))))

  (it "returns nil when no SDK is found anywhere"
    (with-environment-variables (("ZEPHYR_SDK_INSTALL_DIR" nil))
      (let ((zephyr-sdk-search-paths nil))
        (expect (zephyr-sdk-path) :not :to-be-truthy))))

  (it "prefers the highest version when multiple SDKs are found"
    (let ((sdk-old (expand-file-name "zephyr-sdk-0.16.5" dir))
           (sdk-new (expand-file-name "zephyr-sdk-2.0.0" dir)))
      (make-directory sdk-old)
      (make-directory sdk-new)
      (write-region "0.16.5" nil (expand-file-name "sdk_version" sdk-old))
      (write-region "2.0.0"  nil (expand-file-name "sdk_version" sdk-new))
      (with-environment-variables (("ZEPHYR_SDK_INSTALL_DIR" nil))
        (let ((zephyr-sdk-search-paths (list (concat dir "/zephyr-sdk-*"))))
          (expect (zephyr-sdk-path) :to-be-file-equal sdk-new))))))

(describe "zephyr-sdk-version"
  (it "reads and trims the sdk_version file at the given path"
    (ert-with-temp-directory dir
      (write-region "1.5.0\n" nil (expand-file-name "sdk_version" dir))
      (expect (zephyr-sdk-version dir) :to-equal "1.5.0")))

  (it "returns nil when no sdk_version file exists"
    (ert-with-temp-directory dir
      (expect (zephyr-sdk-version dir) :not :to-be-truthy))))

(describe "zephyr-sdk-toolchains"
  (it "returns toolchain subdirectory names from the given SDK path"
    (ert-with-temp-directory dir
      (make-directory (expand-file-name "arm-zephyr-eabi" dir))
      (make-directory (expand-file-name "riscv64-zephyr-elf" dir))
      (make-directory (expand-file-name "xtensa-espressif_esp32s3_zephyr-elf" dir))
      (expect (zephyr-sdk-toolchains dir)
        :to-have-same-items-as
        '("arm-zephyr-eabi"
           "riscv64-zephyr-elf"
           "xtensa-espressif_esp32s3_zephyr-elf"))))

  (it "excludes non-toolchain subdirectories"
    (ert-with-temp-directory dir
      (make-directory (expand-file-name "arm-zephyr-eabi" dir))
      (make-directory (expand-file-name "cmake" dir))
      (make-directory (expand-file-name "hosttools" dir))
      (expect (zephyr-sdk-toolchains dir) :not :to-contain "cmake")
      (expect (zephyr-sdk-toolchains dir) :not :to-contain "hosttools"))))

(describe "zephyr-toolchain-variant"
  (it "honors ZEPHYR_TOOLCHAIN_VARIANT env var, defaulting to \"zephyr\" when unset"
    (with-environment-variables (("ZEPHYR_TOOLCHAIN_VARIANT" "gnuarmemb"))
      (expect (zephyr-toolchain-variant) :to-equal "gnuarmemb"))
    (with-environment-variables (("ZEPHYR_TOOLCHAIN_VARIANT" nil))
      (expect (zephyr-toolchain-variant) :to-equal "zephyr"))))

(describe "zephyr-board"
  (it "honors BOARD env var when set"
    (with-environment-variables (("BOARD" "walter/esp32s3/procpu"))
      (expect (zephyr-board) :to-equal "walter/esp32s3/procpu")))

  (it "falls back to .west/config build.board when env is unset"
    (with-environment-variables (("BOARD" nil))
      (spy-on 'west-config :and-return-value '(("build.board" . "qemu_riscv32")))
      (expect (zephyr-board) :to-equal "qemu_riscv32")))

  (it "returns nil when neither env nor config provide a value"
    (with-environment-variables (("BOARD" nil))
      (spy-on 'west-config :and-return-value nil)
      (expect (zephyr-board) :not :to-be-truthy))))

(describe "zephyr-shield"
  (it "returns nil when SHIELD env is unset"
    (with-environment-variables (("SHIELD" nil))
      (expect (zephyr-shield) :not :to-be-truthy)))

  (it "splits a semicolon-separated SHIELD value into a list"
    (with-environment-variables (("SHIELD" "x_nucleo_iks01a3;adafruit_winc1500"))
      (expect (zephyr-shield)
        :to-equal '("x_nucleo_iks01a3" "adafruit_winc1500"))))

  (it "returns nil when SHIELD is the empty string"
    (with-environment-variables (("SHIELD" ""))
      (expect (zephyr-shield) :not :to-be-truthy))))

(describe "zephyr-snippet"
  (it "returns nil when SNIPPET env is unset"
    (with-environment-variables (("SNIPPET" nil))
      (expect (zephyr-snippet) :not :to-be-truthy)))

  (it "splits a semicolon-separated SNIPPET value into a list"
    (with-environment-variables (("SNIPPET" "cdc-acm-console;rtt-console"))
      (expect (zephyr-snippet) :to-equal '("cdc-acm-console" "rtt-console")))))

(describe "named *-roots accessors"
  (it "each named accessor reads its corresponding env var"
    (with-environment-variables (("BOARD_ROOT"      "/b1")
                                  ("SHIELD_ROOT"     "/sh1")
                                  ("SNIPPET_ROOT"    "/sn1")
                                  ("SOC_ROOT"        "/so1")
                                  ("ARCH_ROOT"       "/ar1")
                                  ("DTS_ROOT"        "/dt1")
                                  ("MODULE_EXT_ROOT" "/mo1"))
      (expect (zephyr-board-roots)      :to-equal '("/b1"))
      (expect (zephyr-shield-roots)     :to-equal '("/sh1"))
      (expect (zephyr-snippet-roots)    :to-equal '("/sn1"))
      (expect (zephyr-soc-roots)        :to-equal '("/so1"))
      (expect (zephyr-arch-roots)       :to-equal '("/ar1"))
      (expect (zephyr-dts-roots)        :to-equal '("/dt1"))
      (expect (zephyr-module-ext-roots) :to-equal '("/mo1"))))

  (it "returns nil when the env var is unset"
    (with-environment-variables (("BOARD_ROOT" nil))
      (expect (zephyr-board-roots) :not :to-be-truthy))))

(describe "zephyr-modules"
  (it "splits ZEPHYR_MODULES into a list of paths, or nil if unset"
    (with-environment-variables (("ZEPHYR_MODULES" (mapconcat #'identity '("/m1" "/m2") path-separator)))
      (expect (zephyr-modules) :to-equal '("/m1" "/m2")))
    (with-environment-variables (("ZEPHYR_MODULES" nil))
      (expect (zephyr-modules) :not :to-be-truthy))))

(describe "zephyr-extra-modules"
  (it "splits EXTRA_ZEPHYR_MODULES into a list of paths, or nil if unset"
    (with-environment-variables (("EXTRA_ZEPHYR_MODULES" (mapconcat #'identity '("/e1" "/e2") path-separator)))
      (expect (zephyr-extra-modules) :to-equal '("/e1" "/e2")))
    (with-environment-variables (("EXTRA_ZEPHYR_MODULES" nil))
      (expect (zephyr-extra-modules) :not :to-be-truthy))))

(describe "zephyr--cmake-arg"
  (it "formats -DKEY=VALUE, joining list values with semicolons, returning nil for nil"
    (expect (zephyr--cmake-arg "BOARD" nil) :not :to-be-truthy)
    (expect (zephyr--cmake-arg "BOARD" "walter/esp32s3/procpu")
      :to-equal "-DBOARD=walter/esp32s3/procpu")
    (expect (zephyr--cmake-arg "BOARD_ROOT" '("/x" "/y" "/z"))
      :to-equal "-DBOARD_ROOT=/x;/y;/z")))

(describe "zephyr-cmake-args"
  (before-each
    (spy-on 'zephyr-board             :and-return-value nil)
    (spy-on 'zephyr-shield            :and-return-value nil)
    (spy-on 'zephyr-snippet           :and-return-value nil)
    (spy-on 'zephyr-toolchain-variant :and-return-value nil)
    (spy-on 'zephyr-sdk-path          :and-return-value nil)
    (spy-on 'zephyr-board-roots       :and-return-value nil)
    (spy-on 'zephyr-shield-roots      :and-return-value nil)
    (spy-on 'zephyr-snippet-roots     :and-return-value nil)
    (spy-on 'zephyr-soc-roots         :and-return-value nil)
    (spy-on 'zephyr-arch-roots        :and-return-value nil)
    (spy-on 'zephyr-dts-roots         :and-return-value nil)
    (spy-on 'zephyr-modules           :and-return-value nil)
    (spy-on 'zephyr-extra-modules     :and-return-value nil))

  (it "returns nil when nothing is set anywhere"
    (expect (zephyr-cmake-args) :not :to-be-truthy))

  (it "emits one -DKEY=VALUE arg per override (lists joined with semicolons)"
    (expect (zephyr-cmake-args '(:board "walter/esp32s3/procpu"))
      :to-equal '("-DBOARD=walter/esp32s3/procpu"))
    (expect (zephyr-cmake-args '(:toolchain-variant "gnuarmemb"))
      :to-equal '("-DZEPHYR_TOOLCHAIN_VARIANT=gnuarmemb"))
    (expect (zephyr-cmake-args '(:shield ("x_nucleo_iks01a3" "adafruit_winc1500")))
      :to-equal '("-DSHIELD=x_nucleo_iks01a3;adafruit_winc1500"))
    (expect (zephyr-cmake-args '(:board-roots ("/extra/boards" "/other/boards")))
      :to-equal '("-DBOARD_ROOT=/extra/boards;/other/boards")))

  (it "emits multiple args in deterministic order"
    (expect (zephyr-cmake-args
              '(:board "walter/esp32s3/procpu"
                 :sdk-path "/opt/zephyr-sdk"
                 :board-roots ("/extra/boards")))
      :to-equal '("-DBOARD=walter/esp32s3/procpu"
                   "-DZEPHYR_SDK_INSTALL_DIR=/opt/zephyr-sdk"
                   "-DBOARD_ROOT=/extra/boards")))

  (it "uses env-derived values when no override is given"
    (spy-on 'zephyr-board :and-return-value "qemu_riscv32")
    (expect (zephyr-cmake-args)
      :to-equal '("-DBOARD=qemu_riscv32")))

  (it "lets an explicit override win over the env-derived value"
    (spy-on 'zephyr-board :and-return-value "qemu_riscv32")
    (expect (zephyr-cmake-args '(:board "walter/esp32s3/procpu"))
      :to-equal '("-DBOARD=walter/esp32s3/procpu"))))

(describe "zephyr-board-id-from-hint"
  (before-each
    (spy-on 'zephyr-boards :and-return-value
      '((:id "walter/esp32s3/procpu"           :name "Walter PROCPU")
         (:id "xiao_esp32s3/esp32s3/procpu"     :name "XIAO ESP32S3 PROCPU")
         (:id "xiao_esp32s3/esp32s3/procpu/sense" :name "XIAO ESP32S3 PROCPU sense")
         (:id "qemu_riscv32"                    :name "QEMU RISC-V")
         (:id "stm32f3_disco"                   :name "STM32F3 Disco"))))

  (it "resolves a slash-replaced hint to the canonical slashed ID"
    (expect (zephyr-board-id-from-hint "walter_esp32s3_procpu")
      :to-equal "walter/esp32s3/procpu"))

  (it "returns IDs without slashes unchanged"
    (expect (zephyr-board-id-from-hint "qemu_riscv32") :to-equal "qemu_riscv32")
    (expect (zephyr-board-id-from-hint "stm32f3_disco") :to-equal "stm32f3_disco"))

  (it "returns nil when no board matches"
    (expect (zephyr-board-id-from-hint "nonexistent_board") :not :to-be-truthy)))

(describe "zephyr-build-dir"
  (it "returns <workspace-root>/build for an explicit workspace"
    (expect (zephyr-build-dir "/some/ws/") :to-equal "/some/ws/build"))

  (it "returns nil when no workspace can be detected"
    (spy-on 'west-workspace-root :and-return-value nil)
    (expect (zephyr-build-dir) :not :to-be-truthy)))

(describe "zephyr-build-command"
  (before-each
    (spy-on 'zephyr-cmake-args :and-return-value
      '("-DBOARD=walter/esp32s3/procpu" "-DZEPHYR_TOOLCHAIN_VARIANT=zephyr"))
    (spy-on 'zephyr-build-dir :and-return-value "/ws/build"))

  (it "composes cmake configure + ninja build chained with &&"
    (expect (zephyr-build-command "/ws/apps/firmware/")
      :to-equal
      "cmake -B /ws/build -GNinja -DBOARD\\=walter/esp32s3/procpu -DZEPHYR_TOOLCHAIN_VARIANT\\=zephyr /ws/apps/firmware && ninja -C /ws/build"))

  (it "strips the trailing slash from the app path"
    (expect (zephyr-build-command "/ws/apps/firmware/")
      :to-match "/ws/apps/firmware && ninja"))

  (it "passes overrides through to zephyr-cmake-args"
    (zephyr-build-command "/ws/apps/firmware/" '(:board "qemu_riscv32"))
    (expect 'zephyr-cmake-args :to-have-been-called-with '(:board "qemu_riscv32")))

  (it "honors a :build-dir override"
    (expect (zephyr-build-command "/ws/apps/firmware/" '(:build-dir "/custom/build"))
      :to-match "cmake -B /custom/build "))

  (it "shell-escapes arguments containing spaces"
    (spy-on 'zephyr-cmake-args :and-return-value '("-DBOARD=foo"))
    (expect (zephyr-build-command "/ws/apps/path with spaces/app")
      :to-match "/ws/apps/path\\\\ with\\\\ spaces/app && ninja")))

(describe "zephyr-build"
  (it "injects ZEPHYR_BASE into the subprocess environment"
    (spy-on 'zephyr-base :and-return-value "/explicit/zephyr/")
    (spy-on 'zephyr-build-command :and-return-value "true")
    (let (captured)
      (spy-on 'compile :and-call-fake
        (lambda (_cmd) (setq captured (getenv "ZEPHYR_BASE"))))
      (zephyr-build "/some/app")
      (expect captured :to-equal "/explicit/zephyr")))

  (it "strips trailing slash from ZEPHYR_BASE before injecting"
    (spy-on 'zephyr-base :and-return-value "/explicit/zephyr/")
    (spy-on 'zephyr-build-command :and-return-value "true")
    (let (captured)
      (spy-on 'compile :and-call-fake
        (lambda (_cmd) (setq captured (getenv "ZEPHYR_BASE"))))
      (zephyr-build "/some/app")
      (expect captured :not :to-match "/$")))

  (it "leaves ZEPHYR_BASE unchanged when zephyr-base returns nil"
    (spy-on 'zephyr-base :and-return-value nil)
    (spy-on 'zephyr-build-command :and-return-value "true")
    (with-environment-variables (("ZEPHYR_BASE" "/preexisting"))
      (let (captured)
        (spy-on 'compile :and-call-fake
          (lambda (_cmd) (setq captured (getenv "ZEPHYR_BASE"))))
        (zephyr-build "/some/app")
        (expect captured :to-equal "/preexisting")))))

(describe "zephyr-build-command with :sysbuild"
  (before-each
    (spy-on 'zephyr-cmake-args :and-return-value '("-DBOARD=walter/esp32s3/procpu"))
    (spy-on 'zephyr-build-dir :and-return-value "/ws/build")
    (spy-on 'zephyr-base :and-return-value "/ws/zephyrproject/zephyr/"))

  (it "uses Zephyr's share/sysbuild as the cmake source dir"
    (expect (zephyr-build-command "/ws/apps/firmware/" '(:sysbuild t))
      :to-match "/ws/zephyrproject/zephyr/share/sysbuild"))

  (it "passes APP_DIR pointing at the user's app"
    (expect (zephyr-build-command "/ws/apps/firmware/" '(:sysbuild t))
      :to-match "-DAPP_DIR\\\\=/ws/apps/firmware"))

  (it "omits the APP_DIR arg when :sysbuild is not set"
    (expect (zephyr-build-command "/ws/apps/firmware/")
      :not :to-match "-DAPP_DIR")))

(describe "zephyr-module-board-roots"
  (it "returns absolute paths from zephyr/module.yml's build.settings.board_root"
    (ert-with-temp-directory dir
      (make-directory (expand-file-name "zephyr" dir))
      (write-region "build:\n  settings:\n    board_root: .\n"
        nil (expand-file-name "zephyr/module.yml" dir))
      (expect (zephyr-module-board-roots dir)
        :to-have-same-items-as (list (directory-file-name dir)))))

  (it "resolves multiple board_root entries when given a list"
    (ert-with-temp-directory dir
      (make-directory (expand-file-name "zephyr" dir))
      (write-region "build:\n  settings:\n    board_root:\n      - ./vendor-a\n      - ./vendor-b\n"
        nil (expand-file-name "zephyr/module.yml" dir))
      (expect (zephyr-module-board-roots dir)
        :to-have-same-items-as
        (list (expand-file-name "vendor-a" dir)
          (expand-file-name "vendor-b" dir)))))

  (it "returns nil when zephyr/module.yml is absent"
    (ert-with-temp-directory dir
      (expect (zephyr-module-board-roots dir) :not :to-be-truthy)))

  (it "returns nil when module.yml has no board_root setting"
    (ert-with-temp-directory dir
      (make-directory (expand-file-name "zephyr" dir))
      (write-region "build:\n  cmake: .\n" nil
        (expand-file-name "zephyr/module.yml" dir))
      (expect (zephyr-module-board-roots dir) :not :to-be-truthy))))

(describe "zephyr-apps"
  :var (dir manifest fw-dir other-dir)
  (before-each
    (spy-on 'west-config :and-return-value nil)
    (setq dir (make-temp-file "zephyr-test-" t))
    (setq manifest (expand-file-name "west.yml" dir))
    (setq fw-dir (expand-file-name "apps/firmware/" dir))
    (setq other-dir (expand-file-name "apps/other/" dir))
    (make-directory (expand-file-name ".west" dir))
    (make-directory fw-dir t)
    (make-directory other-dir t)
    (make-directory (expand-file-name "boards" fw-dir))
    (write-region "manifest:\n  self:\n    import:\n      - apps/firmware/west.yml\n      - apps/other/west.yml\n"
      nil manifest)
    (write-region "" nil (expand-file-name "west.yml" fw-dir))
    (write-region "" nil (expand-file-name "west.yml" other-dir))
    (write-region "find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})\nproject(my_fw)\n"
      nil (expand-file-name "CMakeLists.txt" fw-dir))
    (write-region "find_package(SomethingElse)\nproject(other)\n"
      nil (expand-file-name "CMakeLists.txt" other-dir))
    (write-region "" nil (expand-file-name "boards/walter_esp32s3_procpu.conf" fw-dir))
    (write-region "" nil (expand-file-name "boards/qemu_riscv32.conf" fw-dir)))
  (after-each (delete-directory dir t))

  (it "returns Zephyr-app plists (filtering non-Zephyr apps) with name/path/manifest/boards"
    (let ((apps (zephyr-apps dir)))
      (expect (length apps) :to-equal 1)
      (expect (plist-get (car apps) :name)     :to-equal "my_fw")
      (expect (plist-get (car apps) :path)     :to-equal fw-dir)
      (expect (plist-get (car apps) :manifest) :to-equal
        (expand-file-name "west.yml" fw-dir))
      (expect (plist-get (car apps) :boards)
        :to-have-same-items-as '("walter_esp32s3_procpu" "qemu_riscv32"))))

  (it "returns nil when no workspace exists"
    (ert-with-temp-directory empty
      (expect (zephyr-apps empty) :not :to-be-truthy)))

  (it "falls back to <workspace>/app/ when manifest declares no apps"
    (spy-on 'west-config :and-return-value nil)
    (ert-with-temp-directory ws-dir
      (let ((app-dir (file-name-as-directory (expand-file-name "app" ws-dir))))
        (make-directory (expand-file-name ".west" ws-dir))
        (write-region "manifest:\n  projects: []\n"
          nil (expand-file-name "west.yml" ws-dir))
        (make-directory app-dir t)
        (write-region "find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})\nproject(my_app)\n"
          nil (expand-file-name "CMakeLists.txt" app-dir))
        (let ((apps (zephyr-apps ws-dir)))
          (expect (length apps) :to-equal 1)
          (expect (plist-get (car apps) :name) :to-equal "my_app")
          (expect (plist-get (car apps) :path) :to-be-file-equal app-dir)
          (expect (plist-get (car apps) :manifest) :not :to-be-truthy))))))

(describe "zephyr-patches-yml"
  (it "returns the absolute patches.yml path when present"
    (ert-with-temp-directory dir
      (let ((zephyr (expand-file-name "zephyr" dir)))
        (make-directory zephyr)
        (write-region "" nil (expand-file-name "patches.yml" zephyr))
        (expect (zephyr-patches-yml dir)
          :to-be-file-equal (expand-file-name "zephyr/patches.yml" dir)))))

  (it "returns nil when patches.yml is missing"
    (ert-with-temp-directory dir
      (expect (zephyr-patches-yml dir) :not :to-be-truthy)))

  (it "discovers the current app's patches.yml via zephyr-app-root"
    (ert-with-temp-directory dir
      (write-region "find_package(Zephyr)\nproject(firmware)"
        nil (expand-file-name "CMakeLists.txt" dir))
      (let ((zephyr (expand-file-name "zephyr" dir)))
        (make-directory zephyr)
        (write-region "" nil (expand-file-name "patches.yml" zephyr))
        (let ((default-directory dir))
          (expect (zephyr-patches-yml)
            :to-be-file-equal (expand-file-name "zephyr/patches.yml" dir)))))))

(describe "zephyr--resolve-app"
  (it "prefers an explicit APP-PATH"
    (expect (zephyr--resolve-app "/explicit/app/") :to-equal "/explicit/app/"))

  (it "falls back to the current app via zephyr-app-root"
    (spy-on 'zephyr-app-root :and-return-value "/current/app/")
    (expect (zephyr--resolve-app) :to-equal "/current/app/"))

  (it "auto-picks the only Zephyr app discovered via zephyr-apps"
    (spy-on 'zephyr-app-root :and-return-value nil)
    (spy-on 'zephyr-apps :and-return-value
      '((:name "firmware" :path "/ws/apps/firmware/")))
    (expect (zephyr--resolve-app) :to-equal "/ws/apps/firmware/"))

  (it "prompts when multiple Zephyr apps exist"
    (spy-on 'zephyr-app-root :and-return-value nil)
    (spy-on 'zephyr-apps :and-return-value
      '((:name "firmware"  :path "/ws/apps/firmware/")
         (:name "nuttx-zig" :path "/ws/apps/nuttx-zig/")))
    (spy-on 'completing-read :and-return-value "nuttx-zig")
    (expect (zephyr--resolve-app) :to-equal "/ws/apps/nuttx-zig/"))

  (it "signals user-error when no apps can be discovered"
    (spy-on 'zephyr-app-root :and-return-value nil)
    (spy-on 'zephyr-apps :and-return-value nil)
    (expect (zephyr--resolve-app) :to-throw 'user-error))

  (it "filters apps with the supplied predicate"
    (spy-on 'zephyr-app-root :and-return-value nil)
    (spy-on 'zephyr-apps :and-return-value
      '((:name "firmware"  :path "/ws/apps/firmware/")
         (:name "nuttx-zig" :path "/ws/apps/nuttx-zig/")))
    (let ((accepted '("/ws/apps/firmware/")))
      (expect (zephyr--resolve-app nil (lambda (p) (member p accepted)))
        :to-equal "/ws/apps/firmware/")))

  (it "ignores the current app when it does not satisfy the predicate"
    (spy-on 'zephyr-app-root :and-return-value "/ws/apps/nuttx-zig/")
    (spy-on 'zephyr-apps :and-return-value
      '((:name "firmware"  :path "/ws/apps/firmware/")
         (:name "nuttx-zig" :path "/ws/apps/nuttx-zig/")))
    (expect (zephyr--resolve-app
              nil (lambda (p) (string= p "/ws/apps/firmware/")))
      :to-equal "/ws/apps/firmware/")))

(describe "zephyr-patch-apply"
  (it "invokes `west patch -sm <workspace-relative-app> apply'"
    (ert-with-temp-directory ws
      (let ((app (zephyr-tests--make-workspace-with-app ws "apps/firmware")))
        (spy-on 'compile)
        (zephyr-patch-apply app)
        (expect 'compile :to-have-been-called-with
          "west patch -sm apps/firmware apply"))))

  (it "runs the compile from the workspace root"
    (ert-with-temp-directory ws
      (let* ((app (zephyr-tests--make-workspace-with-app ws "apps/firmware"))
              captured)
        (spy-on 'compile :and-call-fake
          (lambda (&rest _) (setq captured default-directory)))
        (zephyr-patch-apply app)
        (expect captured :to-be-file-equal ws))))

  (it "isolates output into a `*west:patch-apply*' buffer"
    (ert-with-temp-directory ws
      (let ((app (zephyr-tests--make-workspace-with-app ws "apps/firmware"))
             captured)
        (spy-on 'compile :and-call-fake
          (lambda (&rest _)
            (setq captured (funcall compilation-buffer-name-function nil))))
        (zephyr-patch-apply app)
        (expect captured :to-equal "*west:patch-apply*"))))

  (it "signals user-error when no patches.yml is present"
    (ert-with-temp-directory ws
      (make-directory (expand-file-name ".west" ws))
      (spy-on 'compile)
      (expect (zephyr-patch-apply ws) :to-throw 'user-error)
      (expect 'compile :not :to-have-been-called))))

(describe "zephyr-patch-clean"
  (it "invokes `west patch -sm <workspace-relative-app> clean'"
    (ert-with-temp-directory ws
      (let ((app (zephyr-tests--make-workspace-with-app ws "apps/firmware")))
        (spy-on 'compile)
        (zephyr-patch-clean app)
        (expect 'compile :to-have-been-called-with
          "west patch -sm apps/firmware clean"))))

  (it "isolates output into a `*west:patch-clean*' buffer"
    (ert-with-temp-directory ws
      (let ((app (zephyr-tests--make-workspace-with-app ws "apps/firmware"))
             captured)
        (spy-on 'compile :and-call-fake
          (lambda (&rest _)
            (setq captured (funcall compilation-buffer-name-function nil))))
        (zephyr-patch-clean app)
        (expect captured :to-equal "*west:patch-clean*"))))

  (it "signals user-error when no patches.yml is present"
    (ert-with-temp-directory ws
      (make-directory (expand-file-name ".west" ws))
      (spy-on 'compile)
      (expect (zephyr-patch-clean ws) :to-throw 'user-error)
      (expect 'compile :not :to-have-been-called))))

(describe "zephyr-patch-clean-apply"
  (it "chains `clean' then `apply' in a single compile invocation"
    (ert-with-temp-directory ws
      (let ((app (zephyr-tests--make-workspace-with-app ws "apps/firmware")))
        (spy-on 'compile)
        (zephyr-patch-clean-apply app)
        (expect 'compile :to-have-been-called-with
          "west patch -sm apps/firmware clean && west patch -sm apps/firmware apply"))))

  (it "isolates output into a `*west:patch-clean-apply*' buffer"
    (ert-with-temp-directory ws
      (let ((app (zephyr-tests--make-workspace-with-app ws "apps/firmware"))
             captured)
        (spy-on 'compile :and-call-fake
          (lambda (&rest _)
            (setq captured (funcall compilation-buffer-name-function nil))))
        (zephyr-patch-clean-apply app)
        (expect captured :to-equal "*west:patch-clean-apply*")))))

(describe "against example-application (real-world integration)"
  :var (example)
  (before-each
    (setq example (expand-file-name "~/workspace/example-application/"))
    (assume (file-directory-p example)
      "example-application not cloned at ~/workspace/example-application/"))

  (it "identifies app/ as a Zephyr app and root as not"
    (expect (zephyr-app-p (concat example "app/")))
    (expect (zephyr-app-p example) :not :to-be-truthy))

  (it "extracts the project name from app/CMakeLists.txt"
    (expect (zephyr-app-name (concat example "app/")) :to-equal "app"))

  (it "walks up from app/src/ to find the app root"
    (expect (zephyr-app-root (concat example "app/src/"))
      :to-be-file-equal (concat example "app/")))

  (it "finds per-app overlays in app/boards/"
    (expect (zephyr-app-boards (concat example "app/"))
      :to-contain "nucleo_f302r8"))

  (it "ignores HWMv2 board.yml files (no identifier field)"
    (expect (zephyr--parse-board-file
              (concat example "boards/vendor/custom_plank/board.yml"))
      :not :to-be-truthy))

  (it "parses the legacy custom_plank.yaml into a board plist"
    (let ((parsed (zephyr--parse-board-file
                    (concat example "boards/vendor/custom_plank/custom_plank.yaml"))))
      (expect (plist-get parsed :id)        :to-equal "custom_plank")
      (expect (plist-get parsed :name)      :to-equal "Custom-Plank")
      (expect (plist-get parsed :arch)      :to-equal "arm")
      (expect (plist-get parsed :vendor)    :to-equal "vendor")
      (expect (plist-get parsed :supported) :to-equal '("gpio"))))

  (it "discovers app/ via app-walk fallback when manifest declares no apps"
    (spy-on 'west-manifest-apps :and-return-value nil)
    (let ((apps (zephyr-apps example)))
      (expect (length apps) :to-equal 1)
      (expect (plist-get (car apps) :name) :to-equal "app")
      (expect (plist-get (car apps) :path)
        :to-be-file-equal (concat example "app/"))))

  (it "honors zephyr/module.yml settings.board_root for workspace-as-module"
    (expect (zephyr-module-board-roots example)
      :to-have-same-items-as
      (list (directory-file-name example)))))

;;; zephyr-tests.el ends here
