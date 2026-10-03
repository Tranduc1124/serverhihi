ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = APIClientExample
APIClientExample_FILES = Tweak.xm
APIClientExample_CFLAGS += -fobjc-arc -I./APIClient
APIClientExample_LDFLAGS += $(THEOS_PROJECT_DIR)/APIClient/libAPIClient.a
APIClientExample_FRAMEWORKS = Foundation UIKit Security SafariServices

include $(THEOS_MAKE_PATH)/tweak.mk
