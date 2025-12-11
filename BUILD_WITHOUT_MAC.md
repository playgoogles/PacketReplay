# 无需Mac的编译指南

如果你没有Mac电脑，可以使用以下方法编译iOS应用。

---

## ⭐ 方法1：GitHub Actions（最简单，推荐）

完全免费，利用GitHub提供的云端macOS服务器自动编译。

### 步骤：

#### 1. 创建GitHub仓库
```bash
# 在PacketReplay目录下初始化git
cd PacketReplay
git init
git add .
git commit -m "Initial commit"
```

#### 2. 上传到GitHub
- 访问 https://github.com/new 创建新仓库
- 按照提示推送代码：
```bash
git remote add origin https://github.com/你的用户名/PacketReplay.git
git branch -M main
git push -u origin main
```

#### 3. 自动编译
- 推送代码后，GitHub Actions会自动开始编译
- 访问仓库的 **Actions** 标签页查看编译进度
- 编译完成后（约3-5分钟），点击workflow
- 下载 **PacketReplay-IPA** 文件

#### 4. 手动触发编译
- 进入仓库的 **Actions** 标签
- 选择 "Build IPA" workflow
- 点击 **Run workflow** 按钮
- 等待编译完成后下载IPA

### 优点：
✅ 完全免费
✅ 不需要安装任何工具
✅ 支持自动编译
✅ 每次提交代码自动构建

---

## 方法2：使用Theos（Windows/Linux本地编译）

在Windows或Linux上使用Theos工具链编译。

### Windows安装Theos：

#### 1. 安装Git和依赖
下载并安装：
- Git for Windows: https://git-scm.com/download/win
- MSYS2: https://www.msys2.org/

#### 2. 安装Theos
打开Git Bash，运行：
```bash
export THEOS=~/theos
git clone --recursive https://github.com/theos/theos.git $THEOS
```

#### 3. 安装iOS工具链
```bash
# 下载iOS SDK
cd $THEOS
curl -LO https://github.com/theos/sdks/archive/master.zip
unzip master.zip
mv sdks-master sdks
```

#### 4. 编译项目
```bash
cd /c/Users/Administrator/PacketReplay
./build-windows.bat
```

### Linux安装Theos：

#### 1. 一键安装Theos
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
```

#### 2. 编译项目
```bash
cd ~/PacketReplay
chmod +x build-linux.sh
./build-linux.sh
```

### 注意：
- Theos生成的是 `.deb` 格式（越狱包）
- 需要手动转换为IPA才能用于TrollStore
- 或者直接在越狱设备上使用DEB包

---

## 方法3：在线编译服务

使用第三方在线编译服务：

### 3.1 Codemagic（免费额度）
1. 访问 https://codemagic.io
2. 使用GitHub账号登录
3. 连接你的仓库
4. 配置编译流程（使用.github/workflows/build.yml）
5. 启动编译

### 3.2 Bitrise（免费额度）
1. 访问 https://bitrise.io
2. 注册账号
3. 添加应用（从GitHub导入）
4. 配置workflow
5. 开始构建

---

## 方法4：使用朋友的Mac（远程）

如果有朋友有Mac电脑：

### 通过远程桌面：
1. 使用TeamViewer或AnyDesk连接朋友的Mac
2. 在他的Mac上运行编译命令
3. 传输生成的IPA文件

### 通过SSH：
```bash
# 在朋友的Mac上
cd ~/PacketReplay
make build
# 生成PacketReplay.ipa

# 从Windows下载
scp 朋友用户名@Mac的IP:~/PacketReplay/PacketReplay.ipa .
```

---

## 方法对比

| 方法 | 难度 | 费用 | 速度 | 推荐度 |
|------|------|------|------|--------|
| GitHub Actions | ⭐ 简单 | 免费 | 快 | ⭐⭐⭐⭐⭐ |
| Theos (Windows) | ⭐⭐⭐ 中等 | 免费 | 快 | ⭐⭐⭐ |
| 在线服务 | ⭐⭐ 较简单 | 有免费额度 | 中等 | ⭐⭐⭐⭐ |
| 远程Mac | ⭐ 简单 | 免费 | 快 | ⭐⭐⭐ |

---

## 快速开始（推荐GitHub Actions）

### 最快5步完成编译：

```bash
# 1. 进入项目目录
cd C:\Users\Administrator\PacketReplay

# 2. 初始化Git
git init
git add .
git commit -m "抓包重放工具"

# 3. 创建GitHub仓库（在网页上操作）
# 访问 https://github.com/new

# 4. 推送代码
git remote add origin https://github.com/你的用户名/PacketReplay.git
git branch -M main
git push -u origin main

# 5. 等待自动编译完成，下载IPA
# 访问 https://github.com/你的用户名/PacketReplay/actions
```

编译完成后，IPA文件会出现在Actions的Artifacts中！

---

## 故障排除

### GitHub Actions编译失败？
- 检查 `.github/workflows/build.yml` 是否正确上传
- 查看Actions日志找到具体错误
- 确保所有Swift文件语法正确

### Theos编译失败？
- 确认THEOS环境变量已设置
- 检查iOS SDK是否下载
- 运行 `make clean` 后重试

### 无法下载Artifacts？
- 确保已登录GitHub账号
- Actions运行完成后才能下载
- Artifacts保留30天

---

## 需要帮助？

如果遇到问题：
1. 查看GitHub Actions的编译日志
2. 检查Swift代码是否有语法错误
3. 确保所有文件都已正确上传

**最简单的方法就是使用GitHub Actions，不需要安装任何东西！**
