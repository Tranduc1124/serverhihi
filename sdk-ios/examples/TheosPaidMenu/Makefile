ARCHS = arm64
TARGET = iphone:clang:latest:12.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = APIClientPaidMenuExample
APIClientPaidMenuExample_FILES = Tweak.xm
APIClientPaidMenuExample_CFLAGS = -fobjc-arc -I../../../dist/APIClient
APIClientPaidMenuExample_LDFLAGS = $(THEOS_PROJECT_DIR)/../../../dist/APIClient/libAPIClient.a
APIClientPaidMenuExample_FRAMEWORKS = Foundation UIKit Security SafariServices

include $(THEOS_MAKE_PATH)/tweak.mk
