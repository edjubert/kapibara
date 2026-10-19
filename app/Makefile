APP_NAME = Kapibara
APP_BUNDLE = $(APP_NAME).app
CONTENTS = $(APP_BUNDLE)/Contents
APP_DIR = $(HOME)/Applications
KAPITSA_NAME = kapitsa
KAPITSA_EMBED = kapitsa-cli
KAPITSA_BIN ?= $(shell command -v $(KAPITSA_NAME) 2>/dev/null || echo /opt/homebrew/bin/$(KAPITSA_NAME))
APP_VERSION ?= 0.1.0

.PHONY: build app install-app icon clean test

build:
	swift build -c release

test:
	swift test

icon:
	mkdir -p .build
	swiftc scripts/icon/main.swift Sources/Kapibara/KapibaraIcon.swift -o .build/icongen
	.build/icongen Resources/AppIcon.icns

app: build
	@test -x "$(KAPITSA_BIN)" || { echo "error: $(KAPITSA_NAME) not found (looked in PATH and /opt/homebrew/bin)."; echo "Install it first: brew install nace-ai/tap/kapitsa"; exit 1; }
	rm -rf $(APP_BUNDLE)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp .build/release/$(APP_NAME) $(CONTENTS)/MacOS/$(APP_NAME)
	cp -R .build/release/$(APP_NAME)_$(APP_NAME).bundle $(CONTENTS)/MacOS/
	cp "$(KAPITSA_BIN)" $(CONTENTS)/MacOS/$(KAPITSA_EMBED)
	cp Info.plist $(CONTENTS)/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(APP_VERSION)" $(CONTENTS)/Info.plist
	cp Resources/AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns
	# Sign the nested resource bundle first: codesign does not auto-sign
	# sub-bundles living in Contents/MacOS.
	codesign --force --sign - $(CONTENTS)/MacOS/$(APP_NAME)_$(APP_NAME).bundle
	codesign --force --sign - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE) (ad-hoc signed, LSUIElement: no Dock icon)"

install-app: app
	rm -rf "$(APP_DIR)/$(APP_BUNDLE)"
	cp -R $(APP_BUNDLE) "$(APP_DIR)/"
	@echo "Installed to $(APP_DIR)/$(APP_BUNDLE)"
	@echo "Launch it from there, then enable 'Lancer au démarrage' in its settings."

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
