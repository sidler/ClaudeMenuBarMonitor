BUNDLE_ID  := com.sidler.claudemonitor
APP        := build/ClaudeMonitor.app
CONFIG     ?= release
BIN         = $(shell swift build -c $(CONFIG) --show-bin-path)/ClaudeMonitor

.PHONY: all build bundle run demo screenshots icon install uninstall kill clean

all: bundle

build:
	swift build -c $(CONFIG)

# A development build, signed ad-hoc. Enough locally, including notifications
# and the login item -- but an ad-hoc signature is not an identity, so it is no
# use to anybody else's Mac. That is what `make release` is for.
bundle: build
	@Scripts/assemble-bundle.sh "$(APP)" "$(BIN)" "$(BUNDLE_ID)" --sign -
	@echo "built $(APP) (ad-hoc)"

run: kill bundle
	@open "$(APP)"

# The app filled with fabricated sessions: something to look at and click through
# without waiting for a real session to do something worth seeing.
demo: kill
	@swift build -c debug
	@"$(shell swift build -c debug --show-bin-path)/ClaudeMonitor" --demo &
	@echo "running with demo data -- quit it from the panel"

# Redraws the README's pictures from that same demo data. It puts real windows on
# screen and photographs them, so the screen is busy for a few seconds.
screenshots:
	@swift build -c debug
	@"$(shell swift build -c debug --show-bin-path)/ClaudeMonitor" --screenshots docs

# Only needed when the artwork changes; the .icns is checked in.
icon:
	@swift Scripts/make-icon.swift Resources/AppIcon.svg /tmp/ClaudeMonitorIcon.iconset
	@iconutil -c icns /tmp/ClaudeMonitorIcon.iconset -o Resources/AppIcon.icns
	@echo "regenerated Resources/AppIcon.icns"

# MARK: - Release

# Signing and notarising a build for other people's Macs.
#
# Three things have to be true before `make release` works, and none of them can
# be arranged from here:
#
#  1. A "Developer ID Application" certificate in the keychain. It comes from the
#     paid Apple Developer Program: make a certificate request in Keychain Access,
#     upload it at developer.apple.com under Certificates, download the .cer and
#     double-click it. The other kinds do not work -- "Apple Development" is for
#     testing, "Apple Distribution" is for the App Store.
#  2. Notarisation credentials stored under a profile name, once:
#       xcrun notarytool store-credentials "$(NOTARY_PROFILE)" \
#         --apple-id <your-apple-id> --team-id <your-team-id> \
#         --password <an app-specific password from appleid.apple.com>
#     The password is app-specific, not the Apple ID password. A profile stored
#     for another app works just as well: make release NOTARY_PROFILE=<name>.
#  3. A version worth shipping in Resources/Info.plist.
#
# Signing alone is not enough: since macOS 10.15 Gatekeeper refuses a signed but
# un-notarised app with "Apple cannot check it for malicious software".
# Notarising without stapling leaves it needing the network on first launch. This
# does all three.
DEVELOPER_ID := $(shell security find-identity -v -p codesigning 2>/dev/null \
	| grep "Developer ID Application" | head -1 | awk '{print $$2}')
NOTARY_PROFILE ?= ClaudeMonitor
RELEASE_APP := build/release-app/ClaudeMonitor.app
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
ZIP := build/release-app/ClaudeMonitor-$(VERSION).zip

.PHONY: release release-sign release-notarize release-verify

release: release-sign release-notarize release-verify
	@echo
	@echo "$(ZIP) is signed, notarised and stapled."

# Hardened runtime and a secure timestamp: notarisation refuses a build without
# either. No entitlements file, because this app needs none -- it is not
# sandboxed, and under the hardened runtime reading the user's own files and
# spawning a terminal are allowed as they are.
release-sign:
	@test -n "$(DEVELOPER_ID)" || { \
		echo "No \"Developer ID Application\" certificate in the keychain."; \
		echo "See the notes above the release target in the Makefile."; \
		exit 1; \
	}
	@swift build -c release
	@mkdir -p build/release-app
	@Scripts/assemble-bundle.sh "$(RELEASE_APP)" "$(shell swift build -c release --show-bin-path)/ClaudeMonitor" \
		"$(BUNDLE_ID)" --sign $(DEVELOPER_ID) --options runtime --timestamp
	@echo "signed $(RELEASE_APP) with Developer ID"

# ditto rather than zip: the bundle carries symlinks and extended attributes that
# a plain zip drops, and a bundle that reaches Apple without them fails
# notarisation for reasons the log does not make obvious.
release-notarize:
	@/usr/bin/ditto -c -k --keepParent "$(RELEASE_APP)" "$(ZIP)"
	@xcrun notarytool submit "$(ZIP)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	@xcrun stapler staple "$(RELEASE_APP)"
	@rm -f "$(ZIP)"
	@/usr/bin/ditto -c -k --keepParent "$(RELEASE_APP)" "$(ZIP)"

# What another Mac will conclude, asked here rather than found out by the first
# person to download it. `spctl` is Gatekeeper's own verdict and includes the
# notarisation ticket; `stapler validate` proves the ticket travels with the file
# rather than needing the network.
release-verify:
	@codesign --verify --strict --verbose=2 "$(RELEASE_APP)"
	@xcrun stapler validate "$(RELEASE_APP)"
	@spctl --assess --type execute --verbose=4 "$(RELEASE_APP)"

# MARK: - Installing

INSTALLED := /Applications/ClaudeMonitor.app

# rsync rather than rm+cp: replacing the bundle wholesale gives it a fresh
# identity, and macOS then asks again for notification permission on every
# install. Updating in place keeps what the user already allowed.
install: bundle
	@pkill -x ClaudeMonitor 2>/dev/null || true
	@mkdir -p "$(INSTALLED)"
	@rsync -a --delete "$(APP)/" "$(INSTALLED)/"
	@echo "installed $(INSTALLED)"
	@echo "If 'launch at login' was already on, switch it off and on again so the"
	@echo "login item points at the new location."
	@open "$(INSTALLED)"

uninstall:
	@pkill -x ClaudeMonitor 2>/dev/null || true
	@rm -rf "$(INSTALLED)"
	@echo "removed $(INSTALLED)"

# The app has no Dock icon, so a plain relaunch would quietly stack instances.
kill:
	@pkill -x ClaudeMonitor 2>/dev/null || true

clean:
	rm -rf .build build
