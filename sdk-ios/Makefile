# Build static library libAPIClient.a (requires Theos on macOS/Linux)
# Usage:
#   export THEOS=~/theos
#   export TSERVER_CLIENT_API_KEY=...   # 64 hex
#   make clean all
# Output:
#   ../dist/APIClient/libAPIClient.a
#   ../dist/APIClient/APIClient.h
#
# Customer / vendor build is fully automatic:
#   before-all runs scripts/prepare_sdk_build.sh
#     - embed Font Awesome
#     - dual-XOR embed CLIENT_API_KEY
#     - regenerate sealed string/u32 tables (anti-strings / anti-dump of constants)

# Build a universal Apple Silicon archive: arm64 runs on arm64/ arm64e devices,
# while the explicit arm64e slice is available to native arm64e host builds.
ARCHS ?= arm64 arm64e
TARGET ?= iphone:clang:16.5:13.0
DEBUG := 0
FINALPACKAGE := 1
# The bundled Apple cctools strip expects a missing legacy ld on this Linux
# toolchain. Disable only Theos' intermediate strip; after-all uses llvm-strip
# on the final archive and validates every Mach-O member before publication.
STRIP := 0
THEOS_USE_PARALLEL_BUILDING := 0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = libAPIClient
libAPIClient_LINKAGE_TYPE = static
libAPIClient_USE_MODULES := 0

TSERVER_CLIENT_API_KEY := $(strip $(TSERVER_CLIENT_API_KEY))
TSERVER_AUTHORIZATION_PUBLIC_KEYS := $(strip $(TSERVER_AUTHORIZATION_PUBLIC_KEYS))

# `make clean` must work without a secret. Archive builds require key.
ifeq ($(filter-out clean before-clean after-clean,$(MAKECMDGOALS)),)
else
ifeq ($(TSERVER_CLIENT_API_KEY),)
$(error TSERVER_CLIENT_API_KEY is required. Export the CLIENT_API_KEY from server/.env before building.)
endif
ifneq ($(shell printf '%s' '$(TSERVER_CLIENT_API_KEY)' | grep -E '^[[:xdigit:]]{64}$$' >/dev/null && echo ok),ok)
$(error TSERVER_CLIENT_API_KEY must be a 64-character hexadecimal value.)
endif
ifeq ($(TSERVER_AUTHORIZATION_PUBLIC_KEYS),)
$(error TSERVER_AUTHORIZATION_PUBLIC_KEYS is required (kid=/absolute/public-key.pem).)
endif
endif

# Full auto prep — do not require the user to pick offsets/strings.
before-all::
	@chmod +x scripts/prepare_sdk_build.sh scripts/embed_client_api_key.sh scripts/generate_client_identity.sh scripts/generate_sealed_sdk_constants.py scripts/generate_authorization_keyring.py scripts/verify_release_pair.py 2>/dev/null || true
	@TSERVER_CLIENT_API_KEY="$(TSERVER_CLIENT_API_KEY)" TSERVER_AUTHORIZATION_PUBLIC_KEYS="$(TSERVER_AUTHORIZATION_PUBLIC_KEYS)" bash scripts/prepare_sdk_build.sh

libAPIClient_FILES = \
		src/APIClient.mm \
		src/TserverActivationAttempt.mm \
		src/TserverAuth.mm \
		src/TserverAuthBootstrap.mm \
		src/TserverAuthEndpoint.mm \
		src/TserverClientApiKey.mm \
		src/TserverClientApiKeyData.gen.mm \
		src/TserverClientIdentity.mm \
		src/TserverClientIdentityData.gen.mm \
		src/TserverSecretStore.mm \
		src/TserverAuthorizationKeys.gen.mm \
		src/TserverAuthorizationLease.mm \
		src/TserverSecurity.mm \
		src/TserverFridaGuard.mm \
		src/TserverRuntimeIntegrity.mm \
		src/TserverSecurityPolicy.mm \
		src/TserverStringCrypto.mm \
		src/TserverSecureBlob.mm \
		src/TserverSealedConstants.gen.mm \
		src/TserverAntiHook.mm \
		src/TserverAntiPatch.mm \
		src/TserverLogGuard.mm \
		src/TserverTransportSession.mm \
		src/TserverStatus.mm \
		src/TserverDiagnostics.mm \
		src/TserverPinning.mm \
		src/TserverCallbackBridge.mm \
		src/TserverCallbackDedup.mm \
		src/TserverCrypto.mm \
		src/TserverCustomerUI.mm \
		src/TserverHttp.mm \
		src/TserverMemberInfo.mm \
		src/TserverModReady.mm \
		src/TserverPaid.mm \
		src/TserverStorage.mm \
		src/TserverUUIDCallback.mm \
		../sdk-ios-ui/src/TserverComponents.mm \
		../sdk-ios-ui/src/TserverFontAwesome.mm \
		../sdk-ios-ui/src/TserverFontAwesomeData.gen.mm \
		../sdk-ios-ui/src/TserverGateUI.mm \
		../sdk-ios-ui/src/TserverGateView.mm \
		../sdk-ios-ui/src/TserverGateWindow.mm \
		../sdk-ios-ui/src/TserverKeyboard.mm \
		../sdk-ios-ui/src/TserverKeyEntryAssist.mm \
		../sdk-ios-ui/src/TserverTheme.mm \
		../sdk-ios-ui/src/TserverUIConfig.mm \
		$(TSERVER_UI_TEMPLATE_FILES)

include ../sdk-ios-ui/src/Templates.mk

# Release objects must not carry DWARF/source paths. Optimization and hidden
# visibility raise reverse-engineering cost without changing the public ABI.
libAPIClient_CFLAGS = -fobjc-arc -Iinclude -I../sdk-ios-ui/include -include TserverObfuscatedSymbols.h -O2 -g0 -fvisibility=hidden -ffunction-sections -fdata-sections
libAPIClient_CCFLAGS = -include TserverObfuscatedSymbols.h -O2 -g0 -fvisibility=hidden -fvisibility-inlines-hidden -ffunction-sections -fdata-sections
# .mm sources are Objective-C++ and use C++11 constexpr constructors plus C++14
# lambdas (TS_OBF_NS). Without an explicit standard the toolchain falls back to
# C++98 on some hosts, which rejects `constexpr ObfuscatedString(...)` and the
# lambda in TS_OBF_NS. Force the standard in every language-specific block so
# the last -std on the command line is the one that survives.
libAPIClient_CXXFLAGS += -std=c++17
libAPIClient_OBJCXXFLAGS += -std=c++17
libAPIClient_CCFLAGS += -std=c++17
# CLIENT_API_KEY is dual-XOR embedded by prepare_sdk_build — never -D plain hex.
TSERVER_TLS_SPKI_PIN := $(strip $(TSERVER_TLS_SPKI_PIN))
ifeq ($(filter-out clean before-clean after-clean,$(MAKECMDGOALS)),)
else
ifeq ($(TSERVER_TLS_SPKI_PIN),)
$(error TSERVER_TLS_SPKI_PIN is required for a release SDK build.)
endif
ifneq ($(shell printf '%s' '$(TSERVER_TLS_SPKI_PIN)' | grep -E '^[[:xdigit:]]{64}$$' >/dev/null && echo ok),ok)
$(error TSERVER_TLS_SPKI_PIN must be a 64-character hexadecimal SHA-256 SPKI pin.)
endif
libAPIClient_CFLAGS += -DTSERVER_TLS_SPKI_PIN=\"$(TSERVER_TLS_SPKI_PIN)\"
# Customer/release archives bake TSERVER_RELEASE so remote hookKill/logKill soft-disable is ignored.
# Debug Theos builds (THEOS_PACKAGE_SCHEME unset / non-FINALPACKAGE) can omit via TSERVER_RELEASE=0.
ifeq ($(strip $(TSERVER_RELEASE)),0)
else
libAPIClient_CFLAGS += -DTSERVER_RELEASE=1
endif
endif
ifneq ($(strip $(TSERVER_TLS_SPKI_PIN_BACKUP)),)
ifneq ($(shell printf '%s' '$(TSERVER_TLS_SPKI_PIN_BACKUP)' | grep -E '^[[:xdigit:]]{64}$$' >/dev/null && echo ok),ok)
$(error TSERVER_TLS_SPKI_PIN_BACKUP must be a 64-character hexadecimal SHA-256 SPKI pin.)
endif
libAPIClient_CFLAGS += -DTSERVER_TLS_SPKI_PIN_BACKUP=\"$(TSERVER_TLS_SPKI_PIN_BACKUP)\"
endif
libAPIClient_FRAMEWORKS = Foundation UIKit Security SafariServices CoreText SystemConfiguration QuartzCore
libAPIClient_INSTALL_PATH = /usr/lib

include $(THEOS_MAKE_PATH)/library.mk

DIST_DIR = ../dist/APIClient

after-all::
	@LIB_SCAN_PATH="$(THEOS_OBJ_DIR)/libAPIClient.a"; \
		[ -s "$$LIB_SCAN_PATH" ] || LIB_SCAN_PATH=".theos/obj/libAPIClient.a"; \
		[ -s "$$LIB_SCAN_PATH" ] || LIB_SCAN_PATH=".theos/obj/debug/libAPIClient.a"; \
		[ -s "$$LIB_SCAN_PATH" ] || { echo "ERROR: build completed without libAPIClient.a" >&2; exit 1; }; \
		STRIP_TOOL="$$(command -v llvm-strip 2>/dev/null || true)"; \
		[ -n "$$STRIP_TOOL" ] || { echo "ERROR: llvm-strip is required for release SDK packaging" >&2; exit 1; }; \
		mkdir -p $(DIST_DIR); \
		cp -f "$$LIB_SCAN_PATH" "$(DIST_DIR)/.libAPIClient.a.new"; \
		"$$STRIP_TOOL" --strip-debug "$(DIST_DIR)/.libAPIClient.a.new"; \
		cp -f include/APIClient.h "$(DIST_DIR)/.APIClient.h.new"; \
		python3 scripts/verify_release_pair.py --require-arm64e "$(DIST_DIR)/.APIClient.h.new" "$(DIST_DIR)/.libAPIClient.a.new"; \
		TSERVER_RELEASE_FORBIDDEN_CLIENT_KEY="$(TSERVER_CLIENT_API_KEY)" python3 scripts/scan_release_artifact.py "$(DIST_DIR)/.libAPIClient.a.new"; \
		mv -f "$(DIST_DIR)/.libAPIClient.a.new" "$(DIST_DIR)/libAPIClient.a"; \
		mv -f "$(DIST_DIR)/.APIClient.h.new" "$(DIST_DIR)/APIClient.h"
	@echo "Built two-file package -> $(DIST_DIR)"
	@echo "Customer: link libAPIClient.a + APIClient.h; set package token with APIClientConfigure."
