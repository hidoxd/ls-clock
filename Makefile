TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DiagnosticsFix

DiagnosticsFix_FILES = Tweak.x
DiagnosticsFix_CFLAGS = -fobjc-arc
DiagnosticsFix_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKEFILE_PATH)/tweak.mk
