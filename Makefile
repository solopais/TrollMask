# TrollMask — TrollStore 主 App（SwiftUI）
# 注：本 Makefile 只构建主 App；dylib 由 build.sh 先单独构建并放入 layout。
TARGET := iphone:clang:16.5
ARCHS := arm64
SWIFT_VERSION := 5.0
INSTALL_TARGET_PROCESSES =

include $(THEOS)/makefiles/common.mk

APP_NAME := TrollMask
TrollMask_FILES := \
    TrollMaskApp/AppDelegate.swift \
    TrollMaskApp/ContentView.swift \
    TrollMaskApp/DeviceSpoofer.swift \
    TrollMaskApp/AppLauncher.m

TrollMask_FRAMEWORKS := UIKit SwiftUI CoreLocation Foundation
TrollMask_SWIFT_BRIDGING_HEADER := TrollMaskApp/TrollMask-Bridging-Header.h
TrollMask_SWIFT_VERSION := 5.0
TrollMask_CODESIGN_FLAGS := -Sentitlements.plist
TrollMask_INSTALL_PATH := /Applications

include $(THEOS_MAKE_PATH)/application.mk
