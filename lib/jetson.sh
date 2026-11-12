#!/usr/bin/env bash
# Shared, source-only helpers. No commands run when sourced.
validate_jetson_platform() {
  local os=$1 version=$2 arch=$3 l4t=$4
  [[ $os == ubuntu && $version == 22.04 ]] || { echo '需要 Ubuntu 22.04。' >&2; return 1; }
  [[ $arch == arm64 ]] || { echo '需要 ARM64 / aarch64 的 Jetson。' >&2; return 1; }
  [[ $l4t =~ ^#\ R36\ \(release\) ]] || { echo '需要 JetPack 6 / L4T R36；不支持普通 ARM 主机或 JetPack 5。' >&2; return 1; }
}
jetson_platform_check() {
  [[ $(uname -s) == Linux && -r /etc/os-release ]] || { echo '仅支持 Linux。' >&2; return 1; }
  local ID='' VERSION_ID='' l4t model compatible
  . /etc/os-release
  l4t=$(cat /etc/nv_tegra_release 2>/dev/null) || l4t=''
  validate_jetson_platform "$ID" "$VERSION_ID" "$(dpkg --print-architecture)" "$l4t" || return 1
  model=$(tr -d '\0' </proc/device-tree/model 2>/dev/null) || model='unknown'
  compatible=$(tr '\0' '\n' </proc/device-tree/compatible 2>/dev/null) || compatible=''
  printf '设备：%s\n%s\n' "$model" "$l4t"
  if [[ $compatible == *p3767-0000* ]]; then
    echo '识别到 Orin NX 16GB 模组（P3767-0000）。'
  else
    echo '提示：设备树未标明 P3767-0000，请确认硬件为 Orin NX 16GB；第三方载板可能使用自定义设备树。'
  fi
  if [[ $l4t != *'REVISION: 4.3,'* ]]; then
    echo '提示：本版本针对 JetPack 6.2 / L4T 36.4.3 编写，当前 R36 小版本不同，需要实机验证。'
  fi
  free -h
}
jetson_apt_check() {
  local audit
  audit=$(dpkg --audit) || return 1
  if [[ -n $audit ]]; then
    printf '%s\n' "$audit" >&2
    echo 'dpkg 配置未完成。运行 bash install-jetson.sh --repair-apt 后重试。' >&2
    return 1
  fi
  if ! sudo apt-get check; then
    echo 'APT 依赖异常。运行 bash install-jetson.sh --repair-apt 后重试。' >&2
    return 1
  fi
}
jetson_apt_repair() {
  # A broken dependency can make dpkg fail; let APT repair it before retrying.
  if ! sudo dpkg --configure -a; then
    echo 'dpkg 尚有依赖未完成，继续尝试 APT 修复。' >&2
  fi
  # Keep the interactive review and refuse any proposed package removal.
  sudo apt-get --fix-broken install --no-remove || return 1
  sudo dpkg --configure -a || return 1
  jetson_apt_check
}
