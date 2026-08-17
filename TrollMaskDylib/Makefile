# TrollMaskDylib — 编译为 dylib，由主 App 在运行时复制到 /var/tmp 并注入目标进程
TARGET := iphone:clang:16.5
ARCHS := arm64
INSTALL_TARGET_PROCESSES =

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := TrollMaskDylib
TrollMaskDylib_FILES := Tweak.m
TrollMaskDylib_FRAMEWORKS := Foundation UIKit CoreLocation
TrollMaskDylib_LIBRARIES := substrate
TrollMaskDylib_CODESIGN_FLAGS := -Sentitlements.plist

include $(THEOS_MAKE_PATH)/tweak.mk
