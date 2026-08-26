TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LSClock

LSClock_FILES = Tweak.x
LSClock_CFLAGS = -fobjc-arc
LSClock_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKEFILE_PATH)/tweak.mk
