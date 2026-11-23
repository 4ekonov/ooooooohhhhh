# Для rootless (Dopamine, palera1n rootless) раскомментируй строку ниже:
# THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ColorOSCC
ColorOSCC_FILES = Tweak.xm OPCCView.m OPCCActions.m OPCCEditController.m
ColorOSCC_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-unguarded-availability-new -Wno-error
ColorOSCC_FRAMEWORKS = UIKit MediaPlayer AVFoundation CoreLocation AudioToolbox

include $(THEOS_MAKE_PATH)/tweak.mk
