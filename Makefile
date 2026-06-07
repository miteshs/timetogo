# TimeToGo build harness
# Most targets need Xcode (xcodebuild + simulators). `verify-logic` needs only
# the Swift command-line toolchain, so it works before Xcode is installed.

# If full Xcode is installed but `xcode-select` still points at the Command Line
# Tools, use Xcode's toolchain without needing `sudo xcode-select -s`.
ifneq ($(wildcard /Applications/Xcode.app/Contents/Developer),)
export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
endif

SCHEME   := TimeToGo
PROJECT  := TimeToGo.xcodeproj
SIM      ?= iPhone 17
DEST     := platform=iOS Simulator,name=$(SIM)
BUNDLE   := com.mpshah.timetogo
DERIVED  := build

.PHONY: help generate build test run device verify-logic clean

help:
	@echo "TimeToGo make targets:"
	@echo "  make verify-logic  - compile & run pure-logic checks (NO Xcode needed)"
	@echo "  make generate      - regenerate TimeToGo.xcodeproj from project.yml"
	@echo "  make build         - build for the iPhone simulator"
	@echo "  make test          - run the unit tests on the simulator"
	@echo "  make run           - build, boot the simulator, install & launch"
	@echo "  make device        - build for a connected iPhone (set up signing in Xcode first)"
	@echo "  make clean         - remove generated project + build output"

# --- Works today, without Xcode --------------------------------------------
verify-logic:
	@swiftc -O \
		TimeToGo/Services/IntentParser.swift \
		TimeToGo/Services/ReminderSchedule.swift \
		TimeToGo/Services/HistoryStats.swift \
		Scripts/main.swift \
		-o $(DERIVED)/ttg-verify 2>/dev/null || \
	swiftc \
		TimeToGo/Services/IntentParser.swift \
		TimeToGo/Services/ReminderSchedule.swift \
		TimeToGo/Services/HistoryStats.swift \
		Scripts/main.swift \
		-o $(DERIVED)/ttg-verify
	@$(DERIVED)/ttg-verify

# --- Need Xcode -------------------------------------------------------------
generate:
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DEST)' -derivedDataPath $(DERIVED) build

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DEST)' -derivedDataPath $(DERIVED) test

run: build
	@xcrun simctl boot "$(SIM)" 2>/dev/null || true
	@open -a Simulator
	@xcrun simctl bootstatus "$(SIM)" -b
	xcrun simctl install booted "$(DERIVED)/Build/Products/Debug-iphonesimulator/TimeToGo.app"
	xcrun simctl launch booted $(BUNDLE)

device: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'generic/platform=iOS' -derivedDataPath $(DERIVED) \
		-allowProvisioningUpdates build

clean:
	rm -rf $(PROJECT) $(DERIVED)
