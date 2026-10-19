DIST := dist
VERSION ?= $(shell sed -n 's/^APP_VERSION ?= \"\(.*\)\"/\1/p' app/Makefile | head -1)

.PHONY: release app clean

release: app
	mkdir -p $(DIST)
	rm -rf $(DIST)/Kapibara.app
	cp -R app/Kapibara.app $(DIST)/
	ditto -c -k --keepParent app/Kapibara.app $(DIST)/Kapibara-$(VERSION)-macos-arm64.zip
	@echo "Release artifacts in $(DIST)/"

app:
	make -C app app

clean:
	rm -rf $(DIST)
	make -C app clean
