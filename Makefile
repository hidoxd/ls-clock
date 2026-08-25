TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LSClock

LSClock_FILES = Tweak.x
LSClock_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
LSClock_FRAMEWORKS = UIKit Foundation CoreFoundation QuartzCore ImageIO CoreGraphics

include $(THEOS_MAKEFILE_PATH)/tweak.mk
