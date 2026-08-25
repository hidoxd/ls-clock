TARGET := iphone:clang:latest:15.0
INSTALL_TYPE = rootless
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LSClock

LSClock_FILES = Tweak.x
LSClock_CFLAGS = -fobjc-arc
LSClock_FRAMEWORKS = UIKit CoreGraphics

include $(THEOS_MAKEFILE_PATH)/tweak.mkTARGET := iphone:clang:latest:16.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LSClock

LSClock_FILES = Tweak.x
LSClock_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
LSClock_FRAMEWORKS = UIKit Foundation CoreFoundation QuartzCore ImageIO

include $(THEOS_MAKE_PATH)/tweak.mk
LSClock_FRAMEWORKS = UIKit CoreGraphics ImageIO
