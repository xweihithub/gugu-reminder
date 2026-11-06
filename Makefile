SWIFT_ENV = CLANG_MODULE_CACHE_PATH="$(CURDIR)/.build/ModuleCache" SWIFTPM_MODULECACHE_OVERRIDE="$(CURDIR)/.build/ModuleCache"
SWIFT_FLAGS = --disable-sandbox --scratch-path .build --cache-path .build/SwiftPMCache
APP_DIR = dist/mac-$(if $(filter arm64,$(shell uname -m)),arm64,x64)/Golden Paw.app

.PHONY: build run test verify media

build:
	bash tools/build-native.sh

run: build
	open "$(APP_DIR)"

test:
	$(SWIFT_ENV) xcrun swift test $(SWIFT_FLAGS)

verify: build
	bash tools/verify-native.sh

# 仅维护素材时需要 FFmpeg，正常构建和运行无需 FFmpeg。
media:
	bash tools/convert-native-media.sh
