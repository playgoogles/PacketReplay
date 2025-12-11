@echo off
REM Windows批处理脚本 - 使用Theos编译

echo ========================================
echo 使用Theos编译PacketReplay
echo ========================================

REM 检查Theos是否安装
if not defined THEOS (
    echo [错误] 未找到THEOS环境变量
    echo 请先安装Theos for Windows
    echo 下载地址: https://github.com/theos/theos/wiki/Installation-Windows
    pause
    exit /b 1
)

echo THEOS路径: %THEOS%

REM 使用Theos Makefile
if exist Makefile.theos (
    echo 使用Theos配置编译...
    copy /Y Makefile.theos Makefile

    REM 编译
    make clean
    make package

    echo.
    echo ========================================
    echo 编译完成！
    echo IPA文件位置: packages\com.packet.replay_1.0_iphoneos-arm64.deb
    echo 需要转换为IPA格式
    echo ========================================
) else (
    echo [错误] 未找到Makefile.theos
    pause
    exit /b 1
)

pause
