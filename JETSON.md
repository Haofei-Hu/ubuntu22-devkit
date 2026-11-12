# Jetson Orin NX 16GB / JetPack 6.2

目标平台：**Orin NX 16GB（P3767-0000）、ARM64、Ubuntu 22.04、JetPack 6.2 / L4T 36.4.3**。NVIDIA 的对应计算栈为 CUDA 12.6、TensorRT 10.3、cuDNN 9.3。脚本保留已安装的 NVIDIA 计算栈；不刷机、不升级 JetPack、不切换内核、不强制安装桌面版 NVIDIA 驱动、不修改功耗模式。

普通 ARM 电脑、JetPack 5 / Ubuntu 20.04 不适用。其他 L4T R36 小版本会提示差异，仍需在目标机器确认兼容性；脚本不会因为版本差异自动升级或降级。第三方载板请继续使用其厂家匹配的 BSP。

## 下载与安装

已配置 GitHub SSH 公钥时：

```bash
git clone git@github.com:Haofei-Hu/ubuntu22-devkit.git
cd ubuntu22-devkit
bash install-jetson.sh
```

公开仓库也可不登录，通过 HTTPS 下载：

```bash
git clone https://github.com/Haofei-Hu/ubuntu22-devkit.git
cd ubuntu22-devkit
bash install-jetson.sh
```

已有仓库时先进入该目录，使用 `git pull --ff-only` 更新。若 Git 提示本地修改冲突，先保留修改再处理，不要强制覆盖。`bash install.sh` 也会在 ARM64 系统自动进入 Jetson 流程。

**使用普通用户运行，不要 `sudo bash`。** 需要管理员权限时脚本会提示输入密码。每条命令按回车执行，等上一条完成再输入下一条；遇到错误保留完整输出。

仅检查系统信息（不会安装软件）：

```bash
bash install-jetson.sh --check
```

仅安装浏览器、Git、Terminator 及所需的软件源工具：

```bash
bash install-jetson.sh --browser-only
epiphany https://github.com
```

完整开发环境加装 Clash Verge Rev：

```bash
bash install-jetson.sh --with-clash
```

## 先处理 APT / dpkg 中断

出现 `dpkg was interrupted` 或 `unmet dependencies` 时，在仓库目录运行：

```bash
bash install-jetson.sh --repair-apt
```

该模式只修复包管理状态，不继续安装开发环境。依次执行 `dpkg --configure -a`、`apt-get --fix-broken install --no-remove`，再重试配置和检查。如果第一步因为缺依赖失败，会继续尝试 APT 修复；后续仍失败则退出。APT 会显示拟执行的操作供确认，`--no-remove` 阻止通过删除软件包解决依赖。锁被其他程序占用时，等原程序结束后重试，不删除锁文件。

修复完成后重新运行 `bash install-jetson.sh`。如果连 Git 都没有，先运行 `sudo dpkg --configure -a`、`sudo apt --fix-broken install --no-remove` 修复依赖，再用 `sudo apt update` 和 `sudo apt install git` 安装 Git。

## 安装内容与差异

| 功能 | Jetson 版本 |
| --- | --- |
| 浏览器 | Ubuntu APT 的 GNOME Web / Epiphany，使用 `epiphany` 启动，不经过 Snap |
| 编辑器 | Microsoft 官方 APT 源的 ARM64 VS Code，以及 C/C++、CMake、Python 扩展 |
| 开发工具 | GCC/G++、Clang、GDB、CMake、Ninja、Git、Python 3.10、Terminator |
| ROS | ROS 2 Humble Desktop、ros-dev-tools、MAVROS、MAVROS Extras、GeographicLib 数据集 |
| Python | `~/.venvs/robotics-jetson`，继承系统包；基础科学计算包通过 Ubuntu ARM64 APT 安装 |
| 串口 | 当前用户加入 dialout，注销并登录后生效；不自动停用 ModemManager |
| 代理客户端 | 可选 Clash Verge Rev 2.5.10 ARM64 `.deb`，校验固定 SHA-256 和包架构 |
| QGC | 不安装原脚本的 x86_64 AppImage；建议在另一台地面站电脑运行，通过实际网络/串口配置连接 |
| Chrome / ChatGPT 桌面包 | 不安装原脚本的 amd64 包；可用 Epiphany 访问网页 |
| CUDA / TensorRT / cuDNN | 读取现有安装状态，不自动安装、替换或升级 |

`--with-clash` 需要联网下载；代理软件尚未配置时不能为自己的安装自动提供代理。安装后自行导入订阅。Python 环境不自动安装 PyTorch、pip OpenCV 或 NumPy 2；后续 GPU 依赖需匹配当前 JetPack、CUDA 和 Python，避免覆盖厂商包。不要直接复用 x86_64 wheel。

脚本不会执行 `apt upgrade`、安装 `nvidia-driver-*`、修改 `/etc/nv_tegra_release`、配置交换分区或调用 `jetson_clocks`。16GB 为 CPU/GPU 共享内存；构建大型 ROS 工程可从保守的两个并行任务开始，按实测资源使用调整：

```bash
cd ~/ros2_ws
source /opt/ros/humble/setup.bash
MAKEFLAGS=-j2 CMAKE_BUILD_PARALLEL_LEVEL=2 colcon build --symlink-install --parallel-workers 2
```

新 Bash 终端使用 `robotics-python` 激活 Python 环境，`deactivate` 退出。也可手动运行：

```bash
source ~/.venvs/robotics-jetson/bin/activate
```

VS Code 选择该目录下的 `bin/python` 作为解释器。ROS 工作区位于 `~/ros2_ws/src`，需要自行放入项目源码。

## 验证与排错

```bash
bash verify-jetson.sh
```

`bash verify.sh` 在 ARM64 上也会进入同一检查。检查平台、C/C++ 编译、Python/ROS 导入、NumPy 主版本、MAVROS 包、地理数据和桌面软件配置状态；显示可用的 CUDA 编译器及 NVIDIA 包版本。CUDA 缺失会提示，不把它当作开发工具安装失败。

功耗模式编号随模组、载板和刷机配置变化，不能直接把某个编号当成 MAXN。只查询当前模式可运行 `sudo nvpmodel -q`；本脚本不切换 40W / MAXN SUPER。MAVROS 和 QGC 的飞控地址、波特率与路由需按实际系统配置。

**验证边界：** 已提供平台识别和 APT 修复分支的模拟回归测试，可在开发机执行 `python3 tests/test_jetson.py`。安装脚本需要在真实 Orin NX 16GB 上继续验证；尚未宣称完成全流程安装、GUI、GPU 或飞控联调。

## 参考

- [NVIDIA JetPack 6.2 对应系统和计算栈](https://developer.nvidia.com/embedded/jetpack-sdk-62)
- [Orin NX 功耗模式与 Super 配置](https://docs.nvidia.com/jetson/archives/r36.4.3/DeveloperGuide/SD/PlatformPowerAndPerformance/JetsonOrinNanoSeriesJetsonOrinNxSeriesAndJetsonAgxOrinSeries.html)
- [ROS 2 Humble Ubuntu 安装](https://docs.ros.org/en/humble/Installation/Ubuntu-Install-Debs.html)
- [VS Code Linux / ARM64 安装](https://code.visualstudio.com/docs/setup/linux)
- [Ubuntu 22.04 Epiphany ARM64 软件包](https://packages.ubuntu.com/jammy/epiphany-browser)
- [Clash Verge Rev 2.5.10 官方发布](https://github.com/clash-verge-rev/clash-verge-rev/releases/tag/v2.5.10)
