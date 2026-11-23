"""Active Directory scripts, run against a real Samba AD domain created for the tests (CORP.EXAMPLE.TEST)."""
import csv
import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SAMBA_TOOL = os.environ.get("SAMBA_TOOL", "samba-tool")
pytestmark = pytest.mark.skipif(shutil.which(shlex.split(SAMBA_TOOL)[-1]) is None and not Path(shlex.split(SAMBA_TOOL)[-1]).exists(),
                                reason="samba-tool not installed")


@pytest.fixture(scope="module")
def domain(tmp_path_factory):
    d = tmp_path_factory.mktemp("ad")
    subprocess.run(shlex.split(SAMBA_TOOL) + [
        "domain", "provision", "--realm=CORP.EXAMPLE.TEST", "--domain=CORP", "--server-role=dc",
        "--dns-backend=NONE", "--adminpass=Adm1n!Passw0rd#2026", f"--targetdir={d}"],
        check=True, capture_output=True)
    return d


@pytest.fixture
def env(domain, tmp_path):
    return {**os.environ, "SAMBA_TOOL": SAMBA_TOOL, "AD_URL": str(domain / "private/sam.ldb"), "LOG_DIR": str(tmp_path)}


def run(script, *args, env):
    return subprocess.run(["bash", str(ROOT / "ad" / script), *args], env=env, capture_output=True, text=True)


def tool(*args, env):
    out = subprocess.run(shlex.split(SAMBA_TOOL) + list(args) + ["-H", env["AD_URL"]], capture_output=True, text=True, check=True)
    return out.stdout


def attr(user, name, env):
    for line in tool("user", "show", user, f"--attributes={name}", env=env).splitlines():
        if line.startswith(f"{name}: "):
            return line.split(": ", 1)[1]
    return None


def test_onboard_creates_user_in_department_ou_with_groups(env):
    r = run("onboard.sh", "asha.k", "Asha", "Kumar", "Finance", "HD-101", "Accountant", env=env)
    assert r.returncode == 0, r.stderr
    assert "Temporary password" in r.stdout
    assert attr("asha.k", "distinguishedName", env).startswith("CN=Asha Kumar,OU=Finance,OU=Staff,")
    assert attr("asha.k", "pwdLastSet", env) == "0"  # must change password at next login
    groups = set(tool("user", "getgroups", "asha.k", env=env).split("\n")) - {""}
    assert groups == {"Domain Users", "GG-Finance", "GG-Finance-Share", "GG-VPN-Users"}
    log = list(csv.DictReader(open(Path(env["LOG_DIR"]) / "ad-actions.csv")))
    assert log[-1]["action"] == "onboard" and log[-1]["ticket"] == "HD-101"


def test_onboard_rejects_bad_input_and_duplicates(env):
    run("onboard.sh", "dup.user", "Dup", "User", "Sales", "HD-1", env=env)
    assert run("onboard.sh", "dup.user", "Dup", "User", "Sales", "HD-2", env=env).returncode == 3
    assert run("onboard.sh", "Bad User", "B", "U", "Sales", "HD-3", env=env).returncode == 2
    assert run("onboard.sh", "new.user", "N", "U", "Marketing", "HD-4", env=env).returncode == 2


def test_password_reset_sets_must_change_and_refuses_disabled_accounts(env):
    run("onboard.sh", "chris.p", "Chris", "Park", "HR", "HD-10", env=env)
    tool("user", "setpassword", "chris.p", "--newpassword=Ch0sen!Passw0rd#1", env=env)
    assert attr("chris.p", "pwdLastSet", env) != "0"
    r = run("reset-password.sh", "chris.p", "HD-11", env=env)
    assert r.returncode == 0, r.stderr
    assert attr("chris.p", "pwdLastSet", env) == "0"
    tool("user", "disable", "chris.p", env=env)
    assert run("reset-password.sh", "chris.p", "HD-12", env=env).returncode == 4


def test_offboard_disables_removes_groups_and_moves_account(env):
    run("onboard.sh", "ben.t", "Ben", "Tran", "IT", "HD-20", env=env)
    r = run("offboard.sh", "ben.t", "HD-21", env=env)
    assert r.returncode == 0, r.stderr
    assert "removed from 4 group(s)" in r.stdout
    assert int(attr("ben.t", "userAccountControl", env)) & 2  # ACCOUNTDISABLE
    assert attr("ben.t", "distinguishedName", env).startswith("CN=Ben Tran,OU=Disabled Users,")
    assert tool("user", "getgroups", "ben.t", env=env).split() == ["Domain", "Users"]


def test_audit_finds_hygiene_problems(env):
    # a disabled account left in a group, an account outside OU=Staff, and an empty group
    tool("user", "create", "old.contractor", "Old!Contr4ctor#2026", env=env)
    tool("group", "add", "GG-Retired-Project", env=env)
    tool("group", "addmembers", "GG-VPN-Users", "old.contractor", env=env)
    tool("user", "disable", "old.contractor", env=env)
    tool("user", "create", "svc.backup", "Svc!Backup#2026xyz", env=env)
    report = Path(env["LOG_DIR"]) / "audit.csv"
    r = subprocess.run(["bash", str(ROOT / "ad/audit.sh"), str(report)], env={**env, "STALE_DAYS": "0"}, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    rows = {(row["finding"], row["object"]) for row in csv.DictReader(open(report))}
    assert ("disabled-in-groups", "old.contractor") in rows
    assert ("outside-staff-ou", "svc.backup") in rows
    assert ("empty-group", "GG-Retired-Project") in rows
    assert ("never-logged-in", "svc.backup") in rows
    assert not any(obj in {"Administrator", "krbtgt", "Guest"} for _, obj in rows)
