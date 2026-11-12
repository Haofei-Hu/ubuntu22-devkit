"""Host-safe regression tests: no installation, sudo or network calls."""
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
LIB = ROOT / "lib/jetson.sh"


def bash(code, *args):
    return subprocess.run(
        ["bash", "-c", 'set -Eeuo pipefail; source "$1"; shift; ' + code,
         "test", str(LIB), *args], text=True, capture_output=True
    )


class PlatformTests(unittest.TestCase):
    def test_target_platform(self):
        result = bash('validate_jetson_platform "$@"', "ubuntu", "22.04", "arm64",
                      "# R36 (release), REVISION: 4.3, GCID: 123")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_reject_unsupported_platforms(self):
        for os, version, arch, l4t in [
            ("ubuntu", "20.04", "arm64", "# R35 (release)"),
            ("ubuntu", "24.04", "arm64", "# R36 (release)"),
            ("ubuntu", "22.04", "amd64", "# R36 (release)"),
            ("ubuntu", "22.04", "arm64", ""),
            ("debian", "22.04", "arm64", "# R36 (release)"),
        ]:
            with self.subTest(os=os, version=version, arch=arch, l4t=l4t):
                self.assertNotEqual(bash('validate_jetson_platform "$@"',
                                        os, version, arch, l4t).returncode, 0)

    def test_help_is_host_safe(self):
        result = subprocess.run(["bash", str(ROOT / "install-jetson.sh"), "--help"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_arm64_entrypoint_dispatch(self):
        code = '''uname() { echo Linux; }; dpkg() { echo arm64; };
export -f uname dpkg; bash "$1/install.sh" --help'''
        result = bash(code, str(ROOT))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("install-jetson.sh", result.stdout)

    def test_unknown_or_conflicting_options_fail(self):
        for args in [("--typo",), ("--check", "--browser-only"),
                     ("--repair-apt", "--with-clash")]:
            result = subprocess.run(["bash", str(ROOT / "install-jetson.sh"), *args],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)


class AptTests(unittest.TestCase):
    def test_audit_output_blocks_install_even_with_zero_exit(self):
        result = bash('dpkg() { echo "package unpacked but not configured"; }; '
                      'sudo() { echo UNEXPECTED; }; jetson_apt_check')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("UNEXPECTED", result.stdout)

    def test_dependency_errors_block_install(self):
        result = bash('dpkg() { return 0; }; sudo() { return 100; }; jetson_apt_check')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--repair-apt", result.stderr)

    def test_repair_recovers_from_initial_dpkg_dependency_failure(self):
        result = bash('''calls=0
sudo() {
  printf 'CALL %s\n' "$*"
  if [[ $1 == dpkg ]]; then
    calls=$((calls+1)); [[ $calls != 1 ]] || return 1
  fi
  return 0
}
dpkg() { return 0; }
jetson_apt_repair''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("apt-get --fix-broken install --no-remove", result.stdout)
        self.assertEqual(result.stdout.count("CALL dpkg --configure -a"), 2)
        self.assertIn("CALL apt-get check", result.stdout)

    def test_repair_failure_stops_before_final_dpkg(self):
        result = bash('''sudo() {
  printf 'CALL %s\n' "$*"
  if [[ $1 == apt-get ]]; then return 100; fi
}
dpkg() { return 0; }
jetson_apt_repair''')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout.count("CALL dpkg --configure -a"), 1)
        self.assertNotIn("CALL apt-get check", result.stdout)


if __name__ == "__main__":
    unittest.main()
