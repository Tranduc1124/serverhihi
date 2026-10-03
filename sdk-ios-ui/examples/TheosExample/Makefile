ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TserverGateExample

TserverGateExample_FILES = Tweak.xm
TserverGateExample_CFLAGS += -I./TserverSDK
TserverGateExample_LDFLAGS += -L./TserverSDK -lTserverAuth -lTserverGateUI
TserverGateExample_FRAMEWORKS = Foundation UIKit Security SafariServices

include $(THEOS_MAKE_PATH)/tweak.mk
