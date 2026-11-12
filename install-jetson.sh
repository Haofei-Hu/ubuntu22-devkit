#!/usr/bin/env bash
# Jetson Orin NX 16GB: Ubuntu 22.04 / JetPack 6.2 (L4T 36.4.3).
set -Eeuo pipefail
trap 'echo "Jetson 安装未完成：第 $LINENO 行。请保留上方报错；修复后可重新运行。" >&2' ERR
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/lib/jetson.sh"
die() { echo "$*" >&2; exit 1; }
mode=full
with_clash=0
for arg in "$@"; do
  case "$arg" in
    --check|--repair-apt|--browser-only)
      [[ $mode == full ]] || die '一次只能选择一种运行模式。'
      mode=${arg#--} ;;
    --with-clash) with_clash=1 ;;
    --help|-h)
      echo '用法：bash install-jetson.sh [--check | --repair-apt | --browser-only] [--with-clash]'
      echo '默认安装开发环境；--check 仅检查平台；--repair-apt 仅修复 APT；--with-clash 可选安装代理客户端。'
      exit 0 ;;
    *) die "未知参数：$arg" ;;
  esac
done
[[ $with_clash == 0 || $mode == full ]] || die '--with-clash 仅用于完整安装。'
jetson_platform_check
[[ $mode != check ]] || exit 0
[[ $EUID != 0 ]] || die '请用普通用户运行，不要 sudo bash。'
command -v sudo >/dev/null || die '需要 sudo 和管理员账户。'
sudo -v
if [[ $mode == repair-apt ]]; then
  jetson_apt_repair
  echo 'APT 修复完成。继续运行 bash install-jetson.sh 或加 --browser-only。'
  exit 0
fi
jetson_apt_check
cache=$(mktemp -d)
trap 'rm -rf "$cache"' EXIT
fetch() { curl --fail --location --retry 3 --connect-timeout 30 "$1" -o "$2"; }
apt_install() { sudo env DEBIAN_FRONTEND=noninteractive apt-get install --no-remove -y "$@"; }

echo '[1/6] 软件源、浏览器和终端'
sudo apt-get update
apt_install ca-certificates curl gnupg software-properties-common
sudo add-apt-repository -y universe
sudo apt-get update
apt_install epiphany-browser terminator git
if [[ $mode == browser-only ]]; then
  echo '浏览器已安装。运行：epiphany https://github.com'
  exit 0
fi

echo '[2/6] C/C++、Python 与 ROS 2 Humble'
apt_install locales build-essential cmake ninja-build gdb clang clang-format pkg-config \
  unzip python3 python3-dev python3-pip python3-venv python3-numpy python3-matplotlib \
  python3-serial python3-pytest
sudo locale-gen en_US.UTF-8
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
fetch https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest "$cache/ros-release.json"
ros_source_version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tag_name"])' "$cache/ros-release.json")
[[ $ros_source_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die '无法识别 ROS 软件源版本。'
fetch "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ros_source_version}/ros2-apt-source_${ros_source_version}.jammy_all.deb" "$cache/ros2-apt-source.deb"
apt_install "$cache/ros2-apt-source.deb"
sudo apt-get update
apt_install ros-humble-desktop ros-dev-tools ros-humble-mavros ros-humble-mavros-extras

echo '[3/6] VS Code ARM64'
fetch https://packages.microsoft.com/keys/microsoft.asc "$cache/microsoft.asc"
gpg --batch --yes --dearmor -o "$cache/vscode.gpg" "$cache/microsoft.asc"
sudo install -m 644 "$cache/vscode.gpg" /usr/share/keyrings/devkit-vscode.gpg
echo 'deb [arch=arm64 signed-by=/usr/share/keyrings/devkit-vscode.gpg] https://packages.microsoft.com/repos/code stable main' | sudo tee /etc/apt/sources.list.d/devkit-vscode.list >/dev/null
sudo apt-get update
echo 'code code/add-microsoft-repo boolean false' | sudo debconf-set-selections
apt_install code
for extension in ms-vscode.cpptools ms-vscode.cmake-tools ms-python.python; do
  if ! code --install-extension "$extension"; then
    echo "扩展下载失败，可稍后重试：code --install-extension $extension" >&2
  fi
done

echo '[4/6] MAVROS 数据集、串口和 Python 环境'
datasets=/opt/ros/humble/lib/mavros/install_geographiclib_datasets.sh
[[ -f $datasets ]] || die "找不到 MAVROS 数据集脚本：$datasets"
sudo bash "$datasets"
sudo usermod -aG dialout "$(id -un)"
if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
  sudo rosdep init
fi
rosdep update --rosdistro humble
mkdir -p "$HOME/.venvs" "$HOME/.config/ubuntu22-devkit" "$HOME/ros2_ws/src"
# Reuse Ubuntu's ARM64 NumPy/Matplotlib and the JetPack system Python packages.
# Do not replace CUDA, TensorRT, OpenCV or install generic PyPI torch wheels.
python3 -m venv --system-site-packages "$HOME/.venvs/robotics-jetson"
cat > "$HOME/.config/ubuntu22-devkit/env.bash" <<'SH'
if [[ -f /opt/ros/humble/setup.bash ]]; then
  source /opt/ros/humble/setup.bash
fi
if [[ -d /usr/local/cuda/bin ]]; then
  case ":$PATH:" in
    *:/usr/local/cuda/bin:*) ;;
    *) export PATH="/usr/local/cuda/bin:$PATH" ;;
  esac
fi
alias robotics-python='source "$HOME/.venvs/robotics-jetson/bin/activate"'
SH
line='[ -f "$HOME/.config/ubuntu22-devkit/env.bash" ] && source "$HOME/.config/ubuntu22-devkit/env.bash"'
touch "$HOME/.bashrc"
if ! grep -Fqx "$line" "$HOME/.bashrc"; then
  cp -p "$HOME/.bashrc" "$HOME/.bashrc.devkit-backup-$(date +%Y%m%d%H%M%S)"
  printf '\n%s\n' "$line" >> "$HOME/.bashrc"
fi

echo '[5/6] 可选 Clash Verge Rev ARM64'
if [[ $with_clash == 1 ]]; then
  fetch https://github.com/clash-verge-rev/clash-verge-rev/releases/download/v2.5.10/Clash.Verge_2.5.10_arm64.deb "$cache/clash-verge.deb"
  printf '%s  %s\n' 729c3bdc84207984fd894cc0ff14e6451fc9335060b5c7efbe378a9f4dbdf8fd "$cache/clash-verge.deb" | sha256sum --check -
  [[ $(dpkg-deb -f "$cache/clash-verge.deb" Package) == clash-verge && $(dpkg-deb -f "$cache/clash-verge.deb" Architecture) == arm64 ]] || die 'Clash 安装包名称或架构不匹配。'
  apt_install "$cache/clash-verge.deb"
else
  echo '未选择代理客户端。如需安装可重新运行并加 --with-clash。'
fi

echo '[6/6] 验证'
bash "$script_dir/verify-jetson.sh"
if [[ $with_clash == 1 ]]; then
  [[ $(dpkg-query -W -f='${Status}' clash-verge) == 'install ok installed' ]] || die 'Clash 未完整安装。'
fi
echo '完成。注销并重新登录，使 dialout 权限生效。'
echo '启动：epiphany / code / terminator；Python 环境：robotics-python。'
echo 'QGC 请在另一台已支持的地面站电脑运行；Jetson 运行 MAVROS。连接参数需按实际飞控设置。'
