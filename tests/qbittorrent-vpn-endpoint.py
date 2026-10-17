"""Check that malformed or missing VPN profiles cannot open firewall egress."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "hosts/nas/qbittorrent-vpn-endpoint.py"


class EndpointTest(unittest.TestCase):
    def run_profile(self, contents, check=False):
        with tempfile.TemporaryDirectory() as directory:
            profile = Path(directory) / "awg0.conf"
            if contents is not None:
                profile.write_bytes(contents.encode() if isinstance(contents, str) else contents)
            return subprocess.run(
                [sys.executable, str(SCRIPT), str(profile)] + (["--check"] if check else []),
                capture_output=True, text=True, check=False,
            )

    def test_endpoint_only_no_keys(self):
        profile = "[Interface]\nPrivateKey = secret\n[Peer]\nEndpoint = 203.0.113.7:443 # VPN\n"
        result = self.run_profile(profile)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "elements = { 203.0.113.7 . 443 }\n")
        self.assertEqual(result.stderr, "")
        result = self.run_profile(profile, check=True)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_fail_closed_and_reject_tunnel_start(self):
        for profile in [
            None, "", "[Peer]\n", b"\xff",
            "Endpoint = vpn.example.com:443",
            "Endpoint = [2001:db8::1]:443",
            "Endpoint = 999.0.0.1:443",
            "Endpoint = 203.0.113.7:0",
            "Endpoint = 203.0.113.7:65536",
            "Endpoint = 203.0.113.7:443; accept",
            "Endpoint = 203.0.113.7:443\nEndpoint = 203.0.113.8:443",
        ]:
            with self.subTest(profile=profile):
                result = self.run_profile(profile)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                result = self.run_profile(profile, check=True)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main()
