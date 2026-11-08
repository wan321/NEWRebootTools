TARGET := iphone:clang:latest:7.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TOOL_NAME = RebootDaemon

RebootDaemon_FILES = main.m
RebootDaemon_CFLAGS = -fobjc-arc
RebootDaemon_FRAMEWORKS = Foundation
RebootDaemon_CODESIGN_FLAGS = -Sentitlements.plist
RebootDaemon_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tool.mk
