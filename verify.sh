#!/usr/bin/env bash
set -Eeuo pipefail
[[ -f /opt/ros/humble/setup.bash ]] || { echo 'ROS Humble 未安装'; exit 1; }
# ROS environment hooks may reference unset variables.
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
cmake --version
gdb --version | sed -n '1p'
"$HOME/.venvs/robotics/bin/python" -c 'import numpy, matplotlib, serial, pytest, rclpy; print("Python + ROS imports OK")'
for package in mavros mavros_extras mavros_msgs; do
  ros2 pkg prefix "$package"
done
test -s /usr/share/GeographicLib/geoids/egm96-5.pgm
test -x "$HOME/Applications/QGroundControl-4.4.4.AppImage"
missing=0
for package in code google-chrome-stable ros-humble-mavros terminator clash-verge chatgpt; do
  status=$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null) || status=''
  if [[ $status == 'install ok installed' ]]; then
    dpkg-query -W -f='${Package} ${Version} ${Status}\n' "$package"
  else
    echo "未完整安装：$package" >&2
    missing=1
  fi
done
[[ $missing == 0 ]] || { echo '桌面软件检查未通过。ChatGPT 官方包若不兼容 Ubuntu 22.04，请查看安装错误及 README。' >&2; exit 1; }
echo '基本检查通过。Clash Verge、ChatGPT、QGC 图形界面及飞控通信仍需在目标电脑上测试。'
