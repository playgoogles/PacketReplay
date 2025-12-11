.PHONY: all clean build install

PROJECT_NAME = PacketReplay
BUNDLE_ID = com.packet.replay
BUILD_DIR = build
PAYLOAD_DIR = $(BUILD_DIR)/Payload
APP_DIR = $(PAYLOAD_DIR)/$(PROJECT_NAME).app
IPA_FILE = $(PROJECT_NAME).ipa

SOURCES = $(wildcard Sources/*.swift)

all: build

build: clean
	@echo "========================================="
	@echo "构建 $(PROJECT_NAME)"
	@echo "========================================="

	@mkdir -p $(APP_DIR)

	@echo "编译Swift代码..."
	@swiftc -sdk $$(xcrun --sdk iphoneos --show-sdk-path) \
		-target arm64-apple-ios14.0 \
		-O \
		-emit-executable \
		-o $(APP_DIR)/$(PROJECT_NAME) \
		$(SOURCES) || (echo "编译失败！请确保安装了Xcode命令行工具。"; exit 1)

	@echo "复制资源文件..."
	@cp Info.plist $(APP_DIR)/
	@cp Entitlements.plist $(APP_DIR)/

	@chmod +x $(APP_DIR)/$(PROJECT_NAME)

	@echo "打包IPA..."
	@cd $(BUILD_DIR) && zip -qr ../$(IPA_FILE) Payload

	@echo "========================================="
	@echo "构建完成: $(IPA_FILE)"
	@echo "使用TrollStore安装此IPA文件"
	@echo "========================================="

clean:
	@echo "清理构建文件..."
	@rm -rf $(BUILD_DIR) $(IPA_FILE)

install: build
	@echo "请在TrollStore中手动安装 $(IPA_FILE)"
