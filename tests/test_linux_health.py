import subprocess
import tarfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "linux/health-check.sh"


def run(*args, **env):
    return subprocess.run(["bash", str(SCRIPT), *args], capture_output=True, text=True, env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", **env})


def test_ok_warn_and_critical_exit_codes():
    ok = run("--services", "", DISK_WARN="100", DISK_CRIT="101")
    assert "Overall:" in ok.stdout and ok.returncode in (0, 1)  # updates may be pending on the runner
    crit = run("--services", "", DISK_WARN="0", DISK_CRIT="0")
    assert crit.returncode == 2 and "[CRIT] disk /" in crit.stdout


def test_missing_service_is_flagged():
    r = run("--services", "no-such-service-xyz", DISK_WARN="100", DISK_CRIT="101")
    assert "no-such-service-xyz" in r.stdout and r.returncode >= 1


def test_collects_a_diagnostic_bundle_for_escalation(tmp_path):
    r = run("--services", "", "--collect", str(tmp_path), DISK_WARN="100", DISK_CRIT="101")
    bundle = next(tmp_path.glob("diagnostics-*.tar.gz"))
    names = {Path(n).name for n in tarfile.open(bundle).getnames()}
    assert {"health.txt", "uname.txt", "disk.txt", "memory.txt", "top-processes.txt", "recent-logs.txt"} <= names
    assert str(bundle) in r.stdout


def test_rejects_unknown_option():
    assert run("--bogus").returncode == 64
