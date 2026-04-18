.PHONY: build run install uninstall clean help

INSTALL_PATH = $(HOME)/Applications/TouchGate.app
BUILD_PATH = .build/debug/TouchGate

help:
	@echo "TouchGate — macOS menu bar app that gates app launches behind Touch ID"
	@echo ""
	@echo "Available commands:"
	@echo "  make build      Build the app (binary goes to .build/debug/TouchGate)"
	@echo "  make run        Build and run in background (adds to menu bar)"
	@echo "  make install    Build and install to ~/Applications/TouchGate.app"
	@echo "  make uninstall  Remove ~/Applications/TouchGate.app"
	@echo "  make stop       Stop any running TouchGate process"
	@echo "  make clean      Remove build artifacts"

build:
	@echo "🔨 Building TouchGate..."
	swift build -c release
	@echo "✓ Build complete: $(BUILD_PATH)"

run: build
	@echo "🚀 Launching TouchGate..."
	@killall TouchGate 2>/dev/null || true
	@sleep 0.5
	@$(BUILD_PATH) &
	@echo "✓ TouchGate is running. Look for the shield icon in your menu bar."

install: build
	@echo "📦 Installing to $(INSTALL_PATH)..."
	@mkdir -p "$(INSTALL_PATH)/Contents/MacOS"
	@mkdir -p "$(INSTALL_PATH)/Contents/Resources"
	@cp $(BUILD_PATH) "$(INSTALL_PATH)/Contents/MacOS/TouchGate"
	@chmod +x "$(INSTALL_PATH)/Contents/MacOS/TouchGate"
	@cp Sources/Resources/Info.plist "$(INSTALL_PATH)/Contents/Info.plist"
	@echo "✓ Installed to $(INSTALL_PATH)"
	@echo ""
	@echo "To run at startup, add this to your login items:"
	@echo "  System Settings → General → Login Items → + → $(INSTALL_PATH)"

uninstall:
	@echo "🗑  Removing $(INSTALL_PATH)..."
	@rm -rf "$(INSTALL_PATH)"
	@echo "✓ Uninstalled"

stop:
	@echo "⛔ Stopping TouchGate..."
	@killall TouchGate 2>/dev/null && echo "✓ Stopped" || echo "✓ Not running"

clean:
	@echo "🧹 Cleaning build artifacts..."
	@rm -rf .build
	@echo "✓ Clean"
