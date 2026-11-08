TARGET = iOS
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0

# TARGET = simulator:clang:latest:14.0
# ARCHS = x86_64 arm64

INSTALL_TARGET_PROCESSES = RebootTools

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = RebootTools

RebootTools_FILES = AppDelegate.swift RootViewController.swift SettingsViewController.swift DeviceController.m PlistManagerUtils.swift SettingsUtils.swift DaemonManager.swift
RebootTools_FRAMEWORKS = UIKit CoreGraphics
# Copy all files from Resources into the .app bundle. This is required for
# Info.plist, LaunchScreen.storyboardc, and both executable helper tools.
RebootTools_RESOURCE_DIRS = Resources
$(APPLICATION_NAME)_SWIFT_BRIDGING_HEADER += $(APPLICATION_NAME)-Bridging-Header.h
include $(THEOS_MAKE_PATH)/application.mk

$(APPLICATION_NAME)_CODESIGN_FLAGS = -Sentitlements.plist

# SUBPROJECTS += RebootRootHelper
#SUBPROJECTS += RebootUserSpaceHelper
include $(THEOS_MAKE_PATH)/aggregate.mk

after-package::
	@echo "Renaming generated IPA package(s) to .tipa..."
	@for ipa in ./packages/*.ipa; do \
		[ -f "$$ipa" ] || continue; \
		mv "$$ipa" "$${ipa%.ipa}.tipa"; \
	done
