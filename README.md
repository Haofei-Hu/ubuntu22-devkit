# Ubuntu 22.04 开发环境

适用于 **Ubuntu 22.04 Desktop、Intel/AMD x86_64**。使用 Bash 执行，需要联网及 sudo 权限。

## 配置内容

| 类别 | 安装与配置 |
| --- | --- |
| 地面站 | QGroundControl 4.4.4 AppImage、应用菜单入口、`qgroundcontrol` 命令 |
| 编辑器 | VS Code stable；C/C++、CMake Tools、Python 扩展 |
| 浏览器 | Google Chrome stable |
| C / C++ | GCC/G++、Clang、GDB、CMake、Ninja、pkg-config |
| Python | Ubuntu Python 3.10、pip、venv；独立环境含 NumPy < 2、Matplotlib、PySerial、pytest |
| ROS | ROS 2 Humble Desktop、ROS 开发工具、rosdep |
| 飞控通信 | MAVROS、MAVROS Extras、GeographicLib 数据集 |
| 其他 | Git、当前用户 dialout 串口权限、`~/ros2_ws/src` 工作区目录 |

QGroundControl 固定旧版以兼容 Ubuntu 22.04；新版预编译包的系统要求不同。ROS 使用 **ROS 2 Humble**，不是 ROS 1 Noetic。Chrome、VS Code 使用官方 APT 源。

## 安装方法

在新电脑的终端执行：

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/Haofei-Hu/ubuntu22-devkit.git
cd ubuntu22-devkit
bash install.sh
```

使用普通用户运行，不要执行 `sudo bash install.sh`。按提示输入 Ubuntu 登录密码，输入时不会显示字符。安装完成后注销并重新登录，使串口权限生效。

也可以通过 GitHub 的 **Code → Download ZIP** 下载，解压后在文件夹里打开终端，执行 `bash install.sh`。需保留 `install.sh` 和 `verify.sh` 在同一目录。

需要能访问 Ubuntu 软件源、GitHub、ROS、Microsoft、Google、PyPI 和数据集下载服务。网络失败后修复连接，再运行 `bash install.sh`。

## 使用方法

新开 Bash 终端启动软件：

```bash
qgroundcontrol
code
google-chrome-stable
```

使用 Python 独立环境：

```bash
robotics-python
python --version
# 安装自己的 Python 依赖
python -m pip install 包名
# 退出环境
deactivate
```

虚拟环境位于 `~/.venvs/robotics`，可访问系统 ROS Python 包，不替换系统 Python，也不会默认自动激活。VS Code 中执行 **Python: Select Interpreter**，选择 `~/.venvs/robotics/bin/python`。

ROS 会通过 `~/.bashrc` 自动加载；原配置在修改前备份。非 Bash 用户可先运行 `bash`，再执行：

```bash
source ~/.config/ubuntu22-devkit/env.bash
```

工作区构建与加载：

```bash
cd ~/ros2_ws
# 先把自己的 ROS 2 包放入 src，再安装依赖并构建
rosdep install --from-paths src --ignore-src -r -y
colcon build --symlink-install
source install/setup.bash
```

## 验证方法

在仓库目录执行：

```bash
bash verify.sh
```

检查内容包括 C/C++ 编译运行、Python 与 ROS 导入、MAVROS 包、地理数据及桌面软件安装状态。安装脚本末尾会自动执行该检查。

QGC 图形界面、视频和飞控通信需在目标电脑验证。安装完成不代表飞控已连接；串口路径、波特率、UDP 地址和飞控 MAVLink 参数需按设备配置。QGC 与 MAVROS 同时使用时，应分配连接或通过 MAVLink 路由转发。

若 ModemManager 占用飞控串口，且不需要蜂窝网络，可临时停止，之后按需恢复：

```bash
sudo systemctl stop ModemManager
sudo systemctl start ModemManager
```

脚本不会自动停用或卸载该服务。

## 部署范围

- 可在多台 Ubuntu 22.04 amd64 电脑重复执行；不适用于 macOS、ARM 或其他 Ubuntu 版本。
- 这是联网安装脚本，不包含软件本体和离线依赖。
- QGC 固定版本；APT、pip 和扩展使用安装时可用版本，因此不保证各次安装的所有版本完全相同。
- 已完成 Bash 语法及非 Linux 拦截检查，尚未在真实 Ubuntu 22.04 上完成全流程安装实测。

## 官方安装资料

- [ROS 2 Humble](https://docs.ros.org/en/humble/Installation/Ubuntu-Install-Debs.html)
- [MAVROS](https://github.com/mavlink/mavros/blob/ros2/docs/installation.md)
- [QGroundControl 4.4](https://docs.qgroundcontrol.com/Stable_V4.4/en/qgc-user-guide/getting_started/download_and_install.html)
- [VS Code](https://code.visualstudio.com/docs/setup/linux)
