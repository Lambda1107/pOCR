APP_NAME = pOCR
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources
SOURCES = Sources/pOCRApp.swift Sources/OCRService.swift Sources/SettingsView.swift Sources/HotKeyManager.swift Sources/StatusBarController.swift Sources/Logger.swift Sources/CredentialsManager.swift

.PHONY: all clean run package

all: $(APP_BUNDLE)

$(APP_BUNDLE): $(SOURCES) AppIcon.icns
	@echo "Building $(APP_NAME)..."
	@mkdir -p $(MACOS_DIR)
	@mkdir -p $(RESOURCES_DIR)

	# Compile Swift sources
	swiftc $(SOURCES) -o $(MACOS_DIR)/$(APP_NAME) -target arm64-apple-macosx13.0 -framework ServiceManagement

	# Copy Icon
	cp AppIcon.icns $(RESOURCES_DIR)/AppIcon.icns

	# Bundle project files for auto-init (pyproject.toml + uv.lock)
	@cp pyproject.toml $(RESOURCES_DIR)/pyproject.toml
	@cp uv.lock $(RESOURCES_DIR)/uv.lock

	# Bundle Python scripts
	@cp Resources/ocr_local.py $(RESOURCES_DIR)/ocr_local.py
	@cp Resources/ocr_api.py $(RESOURCES_DIR)/ocr_api.py

	# Create Info.plist
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > $(CONTENTS_DIR)/Info.plist
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> $(CONTENTS_DIR)/Info.plist
	@echo '<plist version="1.0">' >> $(CONTENTS_DIR)/Info.plist
	@echo '<dict>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>CFBundleExecutable</key>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <string>$(APP_NAME)</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>CFBundlePackageType</key>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <string>APPL</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>CFBundleIconFile</key>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <string>AppIcon</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>CFBundleIdentifier</key>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <string>com.example.$(APP_NAME)</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>CFBundleName</key>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <string>$(APP_NAME)</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>CFBundleShortVersionString</key>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <string>1.2</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>CFBundleVersion</key>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <string>1</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>LSUIElement</key>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <true/>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>NSHighResolutionCapable</key>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <true/>' >> $(CONTENTS_DIR)/Info.plist
	@echo '</dict>' >> $(CONTENTS_DIR)/Info.plist
	@echo '</plist>' >> $(CONTENTS_DIR)/Info.plist

	# Ad-hoc code signing (Required for Apple Silicon)
	codesign --force --deep --sign - $(APP_BUNDLE)

	@echo "Build complete: $(APP_BUNDLE)"

AppIcon.icns:
	iconutil -c icns $(APP_NAME).iconset -o AppIcon.icns

clean:
	rm -rf $(BUILD_DIR)
	rm -f AppIcon.icns

run: $(APP_BUNDLE)
	open $(APP_BUNDLE)

package: $(APP_BUNDLE)
	@echo "Packaging $(APP_NAME) into DMG..."
	@rm -rf $(BUILD_DIR)/dmg_temp
	@mkdir -p $(BUILD_DIR)/dmg_temp
	@cp -R $(APP_BUNDLE) $(BUILD_DIR)/dmg_temp/
	@cp README.md $(BUILD_DIR)/dmg_temp/README.md
	@ln -s /Applications $(BUILD_DIR)/dmg_temp/Applications
	@rm -f $(BUILD_DIR)/$(APP_NAME).dmg
	hdiutil create -volname "$(APP_NAME)" -srcfolder "$(BUILD_DIR)/dmg_temp" -ov -format UDZO "$(BUILD_DIR)/$(APP_NAME).dmg"
	@rm -rf $(BUILD_DIR)/dmg_temp
	@echo "Package created: $(BUILD_DIR)/$(APP_NAME).dmg"
