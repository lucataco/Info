# Info — build & packaging
#
# Common targets:
#   make icon     regenerate the app icon (PNGs + .icns)
#   make build    Release build into ./build
#   make dmg      build + package a distributable Info.dmg
#   make verify   verify app signature + DMG checksum
#   make notarize submit/staple the DMG (requires NOTARY_PROFILE)
#   make run      build + launch
#   make zip      build + zip Info.app for distribution
#   make release  cut a GitHub release + update the Homebrew tap
#   make test     run unit tests
#   make lint     run SwiftLint (install: brew install swiftlint)
#   make clean    remove build artifacts
#
# For distribution to other Macs, sign with a Developer ID and notarize:
#   make dmg CODE_SIGN_IDENTITY="Developer ID Application: …" DEVELOPMENT_TEAM=TEAMID
#   make notarize NOTARY_PROFILE=your-notarytool-profile

APP_NAME = Info
SCHEME   = Info
PROJECT  = Info.xcodeproj
CONFIG   = Release
BUILD_DIR = build
DERIVED  = $(BUILD_DIR)/DerivedData
APP_PATH = $(DERIVED)/Build/Products/$(CONFIG)/$(APP_NAME).app
DMG      = $(BUILD_DIR)/$(APP_NAME).dmg
ICNS     = tools/$(APP_NAME).icns
VERSION  = $(shell awk -F'"' '/MARKETING_VERSION:/ {print $$2; exit}' project.yml)
ZIP      = $(BUILD_DIR)/$(APP_NAME)-$(VERSION).zip
CODE_SIGN_IDENTITY ?= -
CODE_SIGN_STYLE ?= Manual
DEVELOPMENT_TEAM ?=
NOTARY_PROFILE ?=

XCODE_SIGNING = CODE_SIGN_STYLE="$(CODE_SIGN_STYLE)" CODE_SIGN_IDENTITY="$(CODE_SIGN_IDENTITY)" DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)"

.PHONY: all generate icon build dmg zip release verify notarize run test lint clean

all: dmg

generate:
	xcodegen generate

icon:
	swift tools/make-icon.swift
	iconutil -c icns tools/$(APP_NAME).iconset -o $(ICNS)

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) $(XCODE_SIGNING) build

dmg: icon build
	chmod +x tools/package-dmg.sh
	./tools/package-dmg.sh "$(APP_PATH)" "$(DMG)" "$(ICNS)"

zip: build
	@mkdir -p $(BUILD_DIR)
	rm -f "$(ZIP)"
	ditto -c -k --sequesterRsrc --keepParent "$(APP_PATH)" "$(ZIP)"
	@echo "Created $(ZIP)"
	@shasum -a 256 "$(ZIP)"

release:
	./tools/release.sh $(VERSION)

verify: dmg
	codesign --verify --deep --strict --verbose=2 "$(APP_PATH)"
	hdiutil verify "$(DMG)"
	@if spctl -a -vv --type execute "$(APP_PATH)"; then \
		echo "Gatekeeper execute assessment passed"; \
	else \
		echo "Gatekeeper execute assessment did not pass (expected for ad-hoc builds; use Developer ID + notarization for distribution)"; \
	fi

notarize: dmg
	@if [ -z "$(NOTARY_PROFILE)" ]; then \
		echo "Set NOTARY_PROFILE to a notarytool keychain profile"; \
		exit 1; \
	fi
	xcrun notarytool submit "$(DMG)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(DMG)"
	xcrun stapler validate "$(DMG)"

run: build
	open "$(APP_PATH)"

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS' test

lint:
	@if ! command -v swiftlint >/dev/null 2>&1; then \
		echo "SwiftLint is not installed. Install with: brew install swiftlint"; \
		exit 1; \
	fi
	swiftlint lint --config .swiftlint.yml

clean:
	rm -rf $(BUILD_DIR)
