TARGET := iphone:clang:latest:7.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TOOL_NAME = RebootUserSpaceHelper

RebootUserSpaceHelper_FILES = main.m
RebootUserSpaceHelper_CFLAGS = -fobjc-arc
RebootUserSpaceHelper_CODESIGN_FLAGS = -Sentitlements.plist
RebootUserSpaceHelper_INSTALL_PATH = /usr/local/bin

include $(THEOS_MAKE_PATH)/tool.mk

after-stage::
	@echo "Copying file to parent directory..."
	cp $(THEOS_STAGING_DIR)/usr/local/bin/$(TOOL_NAME) ../$(TOOL_NAME)/
	@echo "Copy completed."
