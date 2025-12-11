#!/bin/bash
# Linux编译脚本 - 使用Theos

echo "========================================"
echo "使用Theos编译PacketReplay"
echo "========================================"

# 检查Theos是否安装
if [ -z "$THEOS" ]; then
    echo "[错误] 未找到THEOS环境变量"
    echo "请先安装Theos"
    echo "安装命令: bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)\""
    exit 1
fi

echo "THEOS路径: $THEOS"

# 使用Theos Makefile
if [ -f "Makefile.theos" ]; then
    echo "使用Theos配置编译..."
    cp Makefile.theos Makefile

    # 编译
    make clean
    make package

    echo ""
    echo "========================================"
    echo "编译完成！"
    echo "DEB文件位置: packages/"
    ls -lh packages/*.deb 2>/dev/null || echo "未找到DEB文件"
    echo "========================================"
else
    echo "[错误] 未找到Makefile.theos"
    exit 1
fi
