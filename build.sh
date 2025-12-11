#!/bin/bash

# 抓包重放工具构建脚本
# 用于TrollStore

set -e

PROJECT_NAME="PacketReplay"
BUNDLE_ID="com.packet.replay"
VERSION="1.0"
BUILD_DIR="build"
PAYLOAD_DIR="${BUILD_DIR}/Payload"
APP_DIR="${PAYLOAD_DIR}/${PROJECT_NAME}.app"

echo "========================================="
echo "开始构建 ${PROJECT_NAME}"
echo "========================================="

# 清理旧的构建文件
echo "清理旧文件..."
rm -rf "${BUILD_DIR}"
mkdir -p "${APP_DIR}"

# 编译Swift文件
echo "编译Swift源代码..."
swiftc -sdk $(xcrun --sdk iphoneos --show-sdk-path) \
    -target arm64-apple-ios14.0 \
    -O \
    -emit-executable \
    -o "${APP_DIR}/${PROJECT_NAME}" \
    Sources/*.swift

# 如果编译失败，尝试使用xcodebuild
if [ $? -ne 0 ]; then
    echo "直接编译失败，尝试使用Xcode项目..."
    echo "请确保已安装Xcode和相关工具链"
    exit 1
fi

# 复制资源文件
echo "复制资源文件..."
cp Info.plist "${APP_DIR}/"
cp Entitlements.plist "${APP_DIR}/"

# 创建必要的目录
mkdir -p "${APP_DIR}/_CodeSignature"

# 设置权限
chmod +x "${APP_DIR}/${PROJECT_NAME}"

# 生成IPA
echo "打包IPA..."
cd "${BUILD_DIR}"
zip -r "${PROJECT_NAME}.ipa" Payload
cd ..

# 移动IPA到根目录
mv "${BUILD_DIR}/${PROJECT_NAME}.ipa" .

echo "========================================="
echo "构建完成！"
echo "IPA文件: ${PROJECT_NAME}.ipa"
echo ""
echo "安装步骤:"
echo "1. 将 ${PROJECT_NAME}.ipa 传输到iOS设备"
echo "2. 在TrollStore中打开IPA文件"
echo "3. 点击安装"
echo "========================================="
