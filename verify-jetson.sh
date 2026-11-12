#!/usr/bin/env bash
set -Eeuo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/lib/jetson.sh"
jetson_platform_check
[[ -f /opt/ros/humble/setup.bash ]] || { echo 'ROS Humble 未安装'; exit 1; }
set +u
source /opt/ros/humble/setup.bash
set -u
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
printf '#include <stdio.h>\nint main(void){puts("C OK");return 0;}\n' > "$scratch/main.c"
printf '#include <iostream>\nint main(){std::cout << "C++ OK" << std::endl;}\n' > "$scratch/main.cpp"
gcc -Wall -Wextra -Werror "$scratch/main.c" -o "$scratch/c-test"
g++ -std=c++17 -Wall -Wextra -Werror "$scratch/main.cpp" -o "$scratch/cpp-test"
"$scratch/c-test"
"$scratch/cpp-test"
"$HOME/.venvs/robotics-jetson/bin/python" -c 'import numpy, matplotlib, serial, pytest, rclpy; assert int(numpy.__version__.split(".")[0]) < 2, "ROS Humble 环境需要 NumPy < 2"; print("Python + ROS imports OK")'
for package in mavros mavros_extras mavros_msgs; do
  ros2 pkg prefix "$package"
done
test -s /usr/share/GeographicLib/geoids/egm96-5.pgm
missing=0
for package in code epiphany-browser terminator ros-humble-desktop ros-humble-mavros ros-humble-mavros-extras; do
  status=$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null) || status=''
  if [[ $status == 'install ok installed' ]]; then
    dpkg-query -W -f='${Package} ${Architecture} ${Version}\n' "$package"
  else
    echo "未完整安装：$package" >&2
    missing=1
  fi
done
[[ $missing == 0 ]] || exit 1
if [[ -x /usr/local/cuda/bin/nvcc ]]; then
  /usr/local/cuda/bin/nvcc --version
else
  echo '提示：未找到 CUDA 编译器。JetPack 可能仅安装运行时；本脚本不会自动更换计算栈。'
fi
# This reports installed compute libraries, not GPU execution success.
for package in nvidia-l4t-core nvidia-jetpack libnvinfer10 libcudnn9-cuda-12; do
  dpkg-query -W -f='${Package} ${Version} ${Status}\n' "$package" 2>/dev/null || true
done
if command -v nvpmodel >/dev/null; then
  echo '查看当前功耗模式：sudo nvpmodel -q（仅查询）。'
fi
echo '开发环境基本检查通过；GPU 运算、浏览器界面、串口和飞控通信仍需实机验证。'
