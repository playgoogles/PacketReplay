@echo off
chcp 65001 >nul
echo ========================================
echo 快速上传到GitHub并自动编译
echo ========================================
echo.

REM 检查是否已安装git
where git >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [错误] 未找到Git
    echo 请先下载安装Git: https://git-scm.com/download/win
    pause
    exit /b 1
)

echo [1/5] 初始化Git仓库...
git init
if %ERRORLEVEL% NEQ 0 (
    echo Git初始化失败
    pause
    exit /b 1
)

echo.
echo [2/5] 添加所有文件...
git add .
git commit -m "抓包重放工具 - 初始版本"

echo.
echo [3/5] 请在GitHub上创建仓库
echo.
echo 步骤：
echo 1. 打开浏览器访问: https://github.com/new
echo 2. 仓库名称输入: PacketReplay
echo 3. 选择 Public（公开）
echo 4. 不要勾选任何初始化选项
echo 5. 点击 Create repository
echo.
pause

echo.
set /p GITHUB_USER="[4/5] 输入你的GitHub用户名: "
set /p REPO_NAME="[4/5] 输入仓库名称 [PacketReplay]: "
if "%REPO_NAME%"=="" set REPO_NAME=PacketReplay

echo.
echo [5/5] 推送代码到GitHub...
git remote add origin https://github.com/%GITHUB_USER%/%REPO_NAME%.git
git branch -M main
git push -u origin main

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo ✓ 上传成功！
    echo ========================================
    echo.
    echo 接下来：
    echo 1. 访问: https://github.com/%GITHUB_USER%/%REPO_NAME%/actions
    echo 2. 等待编译完成（约3-5分钟）
    echo 3. 点击最新的workflow运行
    echo 4. 下载 PacketReplay-IPA 文件
    echo 5. 解压得到IPA文件
    echo 6. 传输到iPhone并用TrollStore安装
    echo.
    echo 编译页面将在5秒后自动打开...
    timeout /t 5 >nul
    start https://github.com/%GITHUB_USER%/%REPO_NAME%/actions
) else (
    echo.
    echo [错误] 推送失败
    echo 可能原因：
    echo 1. GitHub用户名或仓库名输入错误
    echo 2. 没有配置Git凭据
    echo 3. 网络连接问题
    echo.
    echo 请手动执行以下命令：
    echo git remote add origin https://github.com/%GITHUB_USER%/%REPO_NAME%.git
    echo git branch -M main
    echo git push -u origin main
)

echo.
pause
