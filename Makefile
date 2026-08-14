TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e
INSTALL_TARGET_PROCESSES := SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LSClock

LSClock_FILES = Tweak.x
LSClock_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-error
LSClock_FRAMEWORKS = UIKit CoreGraphics ImageIO Foundation

include $(THEOS_MAKE_PATH)/tweak.mkTARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e
INSTALL_TARGET_PROCESSES := SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LSClock

LSClock_FILES = Tweak.x
LSClock_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-error
LSClock_FRAMEWORKS = UIKit WebKit CoreGraphics Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
