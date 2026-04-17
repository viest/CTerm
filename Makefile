.PHONY: all clean zig swift app run test dev watch dmg

APP_NAME = CTerm
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
APP_STAGING_BUNDLE = $(BUILD_DIR)/$(APP_NAME).staging.app
APP_PREVIOUS_BUNDLE = $(BUILD_DIR)/$(APP_NAME).previous.app
DMG_OUTPUT = $(BUILD_DIR)/$(APP_NAME).dmg
SWIFT_SOURCES = $(wildcard macos/CTerm/*.swift)
CTERM_ARCHIVE = zig-out/lib/libcterm.a
ICON_SOURCE = macos/Resources/AppIcon-1024.png
ICONSET_DIR = $(BUILD_DIR)/AppIcon.iconset
ICON_FILE = $(BUILD_DIR)/AppIcon.icns

SWIFT_FRAMEWORKS = -framework AppKit -framework Foundation -framework Metal -framework QuartzCore -framework MetalKit -framework CoreGraphics -framework CoreText -framework IOKit -framework Carbon -framework Cocoa -framework UniformTypeIdentifiers -lc++ -lz
SWIFT_ARCH = -target arm64-apple-macosx14.0
GHOSTTY_FLAGS = -import-objc-header macos/CTerm/ghostty_bridge.h -I vendor/ghostty/include -L vendor/ghostty/lib -lghostty
CTERM_FLAGS = -I include -I zig-out/include -L zig-out/lib -lcterm

$(ICON_FILE): $(ICON_SOURCE)
	@rm -rf $(ICONSET_DIR)
	@mkdir -p $(ICONSET_DIR)
	@sips -z 16 16 $(ICON_SOURCE) --out $(ICONSET_DIR)/icon_16x16.png >/dev/null
	@sips -z 32 32 $(ICON_SOURCE) --out $(ICONSET_DIR)/icon_16x16@2x.png >/dev/null
	@sips -z 32 32 $(ICON_SOURCE) --out $(ICONSET_DIR)/icon_32x32.png >/dev/null
	@sips -z 64 64 $(ICON_SOURCE) --out $(ICONSET_DIR)/icon_32x32@2x.png >/dev/null
	@sips -z 128 128 $(ICON_SOURCE) --out $(ICONSET_DIR)/icon_128x128.png >/dev/null
	@sips -z 256 256 $(ICON_SOURCE) --out $(ICONSET_DIR)/icon_128x128@2x.png >/dev/null
	@sips -z 256 256 $(ICON_SOURCE) --out $(ICONSET_DIR)/icon_256x256.png >/dev/null
	@sips -z 512 512 $(ICON_SOURCE) --out $(ICONSET_DIR)/icon_256x256@2x.png >/dev/null
	@sips -z 512 512 $(ICON_SOURCE) --out $(ICONSET_DIR)/icon_512x512.png >/dev/null
	@sips -z 1024 1024 $(ICON_SOURCE) --out $(ICONSET_DIR)/icon_512x512@2x.png >/dev/null
	@iconutil -c icns $(ICONSET_DIR) -o $(ICON_FILE)

all: app

zig:
	zig build -Doptimize=ReleaseFast
	bash ./scripts/repack-zig-static-lib.sh $(CTERM_ARCHIVE)

swift: zig
	@mkdir -p $(BUILD_DIR)
	swiftc $(SWIFT_SOURCES) $(SWIFT_ARCH) $(SWIFT_FRAMEWORKS) $(GHOSTTY_FLAGS) $(CTERM_FLAGS) -o $(BUILD_DIR)/$(APP_NAME) -O -whole-module-optimization

app: swift $(ICON_FILE)
	@rm -rf $(APP_STAGING_BUNDLE)
	@mkdir -p $(APP_STAGING_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_STAGING_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_STAGING_BUNDLE)/Contents/MacOS/
	@cp macos/Resources/Info.plist $(APP_STAGING_BUNDLE)/Contents/
	@cp $(ICON_FILE) $(APP_STAGING_BUNDLE)/Contents/Resources/AppIcon.icns
	@cp vendor/ghostty/lib/Ghostty.metallib $(APP_STAGING_BUNDLE)/Contents/Resources/ 2>/dev/null || true
	@bash ./scripts/sign-app-bundle.sh "$(APP_STAGING_BUNDLE)"
	@rm -rf $(APP_PREVIOUS_BUNDLE)
	@if [ -d "$(APP_BUNDLE)" ]; then mv "$(APP_BUNDLE)" "$(APP_PREVIOUS_BUNDLE)"; fi
	@mv "$(APP_STAGING_BUNDLE)" "$(APP_BUNDLE)"
	@if ! pgrep -x $(APP_NAME) >/dev/null 2>&1; then rm -rf "$(APP_PREVIOUS_BUNDLE)"; fi
	@echo "Built $(APP_BUNDLE)"

run: app
	@open $(APP_BUNDLE)

test:
	zig build test

dev: $(ICON_FILE)
	zig build
	bash ./scripts/repack-zig-static-lib.sh $(CTERM_ARCHIVE)
	@mkdir -p $(BUILD_DIR)
	swiftc $(SWIFT_SOURCES) $(SWIFT_ARCH) $(SWIFT_FRAMEWORKS) $(GHOSTTY_FLAGS) $(CTERM_FLAGS) -o $(BUILD_DIR)/$(APP_NAME)
	@rm -rf $(APP_STAGING_BUNDLE)
	@mkdir -p $(APP_STAGING_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_STAGING_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_STAGING_BUNDLE)/Contents/MacOS/
	@cp macos/Resources/Info.plist $(APP_STAGING_BUNDLE)/Contents/
	@cp $(ICON_FILE) $(APP_STAGING_BUNDLE)/Contents/Resources/AppIcon.icns
	@cp vendor/ghostty/lib/Ghostty.metallib $(APP_STAGING_BUNDLE)/Contents/Resources/ 2>/dev/null || true
	@bash ./scripts/sign-app-bundle.sh "$(APP_STAGING_BUNDLE)"
	@rm -rf $(APP_PREVIOUS_BUNDLE)
	@if [ -d "$(APP_BUNDLE)" ]; then mv "$(APP_BUNDLE)" "$(APP_PREVIOUS_BUNDLE)"; fi
	@mv "$(APP_STAGING_BUNDLE)" "$(APP_BUNDLE)"
	@if ! pgrep -x $(APP_NAME) >/dev/null 2>&1; then rm -rf "$(APP_PREVIOUS_BUNDLE)"; fi
	@echo "Dev build: $(APP_BUNDLE)"

watch:
	./scripts/dev-watch.sh

dmg: app
	bash ./scripts/create-dmg.sh --app "$(APP_BUNDLE)" --output "$(DMG_OUTPUT)"

clean:
	rm -rf $(BUILD_DIR) zig-out .zig-cache
