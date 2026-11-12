#!/usr/bin/env bash
# Ubuntu 22.04 amd64 desktop; run as your regular user, not sudo bash.
set -Eeuo pipefail
trap 'echo "安装未全部完成：第 $LINENO 行。请根据上方错误检查网络、软件源或系统兼容性后重新运行。" >&2' ERR
die() { echo "$*" >&2; exit 1; }
[[ $(uname -s) == Linux && -r /etc/os-release ]] || die '仅支持 Ubuntu Linux。'
. /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 22.04 ]] || die '仅支持 Ubuntu 22.04。'
[[ $(dpkg --print-architecture) == amd64 ]] || die '仅支持 Intel/AMD amd64，不支持 ARM。'
[[ $EUID != 0 ]] || die '请用普通用户运行 bash install.sh，不要使用 sudo bash。'
command -v sudo >/dev/null || die '需要 sudo 和管理员账户。'
sudo -v
cache=$(mktemp -d)
trap 'rm -rf "$cache"' EXIT
fetch() { curl --fail --location --retry 3 --connect-timeout 30 "$1" -o "$2"; }
apt_install() { sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"; }

echo '[1/9] 基础工具、C/C++、Python、QGC 依赖'
sudo apt-get update
apt_install ca-certificates curl gnupg software-properties-common locales \
  build-essential cmake ninja-build gdb clang clang-format pkg-config git unzip \
  python3 python3-dev python3-pip python3-venv \
  libfuse2 libqt5gui5 libxcb-xinerama0 libxkbcommon-x11-0 \
  gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-gl
sudo add-apt-repository -y universe
sudo locale-gen en_US.UTF-8
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

echo '[2/9] ROS 2 Humble 软件源'
# Official ros2-apt-source package maintains the repository key.
fetch https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest "$cache/ros-release.json"
ros_source_version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tag_name"])' "$cache/ros-release.json")
[[ $ros_source_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die '无法识别 ROS 软件源版本。'
fetch "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ros_source_version}/ros2-apt-source_${ros_source_version}.jammy_all.deb" "$cache/ros2-apt-source.deb"
sudo dpkg -i "$cache/ros2-apt-source.deb"

echo '[3/9] VS Code、Google Chrome 和 Terminator'
fetch https://packages.microsoft.com/keys/microsoft.asc "$cache/microsoft.asc"
gpg --batch --yes --dearmor -o "$cache/vscode.gpg" "$cache/microsoft.asc"
sudo install -m 644 "$cache/vscode.gpg" /usr/share/keyrings/devkit-vscode.gpg
echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/devkit-vscode.gpg] https://packages.microsoft.com/repos/code stable main' | sudo tee /etc/apt/sources.list.d/devkit-vscode.list >/dev/null
fetch https://dl.google.com/linux/linux_signing_key.pub "$cache/google.asc"
gpg --batch --yes --dearmor -o "$cache/google.gpg" "$cache/google.asc"
sudo install -m 644 "$cache/google.gpg" /usr/share/keyrings/devkit-google.gpg
# Use Google's standard filename so its package does not create a duplicate.
echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/devkit-google.gpg] https://dl.google.com/linux/chrome/deb/ stable main' | sudo tee /etc/apt/sources.list.d/google-chrome.list >/dev/null
sudo apt-get update
echo 'code code/add-microsoft-repo boolean false' | sudo debconf-set-selections
apt_install code google-chrome-stable terminator ros-humble-desktop ros-dev-tools \
  ros-humble-mavros ros-humble-mavros-extras

echo '[4/9] MAVROS 地理数据、串口权限'
datasets=/opt/ros/humble/lib/mavros/install_geographiclib_datasets.sh
[[ -f $datasets ]] || die "找不到 MAVROS 数据集安装程序：$datasets"
sudo bash "$datasets"
sudo usermod -aG dialout "$(id -un)"
# Preserve ModemManager: some users rely on mobile networking.
if systemctl is-active --quiet ModemManager 2>/dev/null; then
  echo '提示：ModemManager 正在运行。如果飞控串口被占用，可参考 README 停止服务。'
fi
if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
  sudo rosdep init
fi
rosdep update --rosdistro humble

echo '[5/9] QGroundControl 4.4.4（固定版本以兼容 Ubuntu 22.04）'
mkdir -p "$HOME/Applications" "$HOME/.local/bin" "$HOME/.local/share/applications"
fetch https://github.com/mavlink/qgroundcontrol/releases/download/v4.4.4/QGroundControl.AppImage "$cache/QGroundControl.AppImage"
# Check the downloaded file format before installing it.
python3 - "$cache/QGroundControl.AppImage" <<'PY'
import sys
with open(sys.argv[1], 'rb') as f:
    if f.read(4) != b'\x7fELF':
        raise SystemExit('下载的 QGC 不是有效 ELF 文件')
PY
install -m 755 "$cache/QGroundControl.AppImage" "$HOME/Applications/QGroundControl-4.4.4.AppImage"
cat > "$HOME/.local/bin/qgroundcontrol" <<'SH'
#!/usr/bin/env bash
exec "$HOME/Applications/QGroundControl-4.4.4.AppImage" "$@"
SH
chmod +x "$HOME/.local/bin/qgroundcontrol"
cat > "$HOME/.local/share/applications/devkit-qgroundcontrol.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=QGroundControl 4.4.4
Exec="$HOME/.local/bin/qgroundcontrol"
Icon=applications-engineering
Terminal=false
Categories=Development;Science;
EOF

echo '[6/9] Python 虚拟环境和终端配置'
mkdir -p "$HOME/.venvs" "$HOME/.config/ubuntu22-devkit" "$HOME/ros2_ws/src"
python3 -m venv --system-site-packages "$HOME/.venvs/robotics"
"$HOME/.venvs/robotics/bin/python" -m pip install --upgrade pip
"$HOME/.venvs/robotics/bin/python" -m pip install 'numpy<2' matplotlib pyserial pytest
# No automatic venv activation: leave ROS CLI on Ubuntu's Python.
cat > "$HOME/.config/ubuntu22-devkit/env.bash" <<'SH'
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
if [[ -f /opt/ros/humble/setup.bash ]]; then
  source /opt/ros/humble/setup.bash
fi
alias robotics-python='source "$HOME/.venvs/robotics/bin/activate"'
SH
line='[ -f "$HOME/.config/ubuntu22-devkit/env.bash" ] && source "$HOME/.config/ubuntu22-devkit/env.bash"'
touch "$HOME/.bashrc"
if ! grep -Fqx "$line" "$HOME/.bashrc"; then
  cp -p "$HOME/.bashrc" "$HOME/.bashrc.devkit-backup-$(date +%Y%m%d%H%M%S)"
  printf '\n%s\n' "$line" >> "$HOME/.bashrc"
fi
# Extensions are helpful but Marketplace outages must not hide core installation success.
for extension in ms-vscode.cpptools ms-vscode.cmake-tools ms-python.python; do
  if ! code --install-extension "$extension"; then
    echo "扩展安装失败，请稍后重试：code --install-extension $extension" >&2
  fi
done

echo '[7/9] Clash Verge Rev 2.5.10'
# Pin the inspected amd64 release (glibc 2.35 / Ubuntu 22.04).
fetch https://github.com/clash-verge-rev/clash-verge-rev/releases/download/v2.5.10/Clash.Verge_2.5.10_amd64.deb "$cache/clash-verge.deb"
printf '%s  %s\n' add8564811ba4d2305da443288d23a26c5ed19674b676a0bb58b99ec4f7d13cf "$cache/clash-verge.deb" | sha256sum --check -
[[ $(dpkg-deb -f "$cache/clash-verge.deb" Package) == clash-verge && $(dpkg-deb -f "$cache/clash-verge.deb" Architecture) == amd64 ]] || die 'Clash Verge 安装包名称或架构不匹配。'
apt_install --no-remove "$cache/clash-verge.deb"

echo '[8/9] 下载官方 ChatGPT .deb 并尝试安装'
echo '注意：Ubuntu 22.04 不在 ChatGPT 官方支持列表中，安装或启动可能失败。'
chatgpt_dir="$HOME/Downloads/ubuntu22-devkit"
mkdir -p "$chatgpt_dir"
chatgpt_deb="$chatgpt_dir/chatgpt_amd64.deb"
fetch https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb "$cache/chatgpt.deb"
[[ $(dpkg-deb -f "$cache/chatgpt.deb" Package) == chatgpt && $(dpkg-deb -f "$cache/chatgpt.deb" Architecture) == amd64 ]] || die 'ChatGPT 安装包名称或架构不匹配。'
install -m 644 "$cache/chatgpt.deb" "$chatgpt_deb"
chatgpt_failed=0
if ! apt_install --no-remove "$chatgpt_deb"; then
  chatgpt_failed=1
  echo "ChatGPT 安装失败；官方安装包已保留：$chatgpt_deb" >&2
  echo '请检查上方 APT 错误；若依赖版本不兼容，请升级到官方支持的系统。' >&2
fi

echo '[9/9] 验证'
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bash "$script_dir/verify.sh"
[[ $chatgpt_failed == 0 ]] || die '其他检查已完成，但本次 ChatGPT 安装失败。'
echo '完成。请注销并重新登录，使 dialout 串口权限生效。'
echo '新终端输入：qgroundcontrol / code / google-chrome-stable / terminator / clash-verge / chatgpt'
echo 'Clash Verge 需自行导入订阅；ChatGPT 需登录，并在目标电脑确认能正常启动。'
echo 'Python 虚拟环境：robotics-python；退出：deactivate'
echo 'MAVROS 已安装，但飞控连接地址需按你的硬件设置。'
