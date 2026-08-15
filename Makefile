TARGET := iphone:clang:latest:16.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LSClock

LSClock_FILES = Tweak.x
LSClock_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
LSClock_FRAMEWORKS = UIKit Foundation CoreFoundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
