TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LSClock
LSClock_FILES = Tweak.x
LSClock_CFLAGS = -fobjc-arc
LSClock_FRAMEWORKS = UIKit WebKit

include $(THEOS_MAKE_PATH)/tweak.mk
