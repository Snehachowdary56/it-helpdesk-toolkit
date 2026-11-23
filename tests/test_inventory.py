from datetime import date

import pytest

from inventory.inventory import Inventory, InventoryError, main


@pytest.fixture
def inv(tmp_path):
    i = Inventory(tmp_path / "equipment.csv")
    i.add("LT-0001", "laptop", "Dell Latitude 5440", "SN1", "2027-01-15")
    i.add("LT-0002", "laptop", "Dell Latitude 5440", "SN2", "2028-06-30")
    i.add("MN-0001", "monitor", "Dell P2423", "SN3", "2026-10-01")
    i.add("KB-0001", "keyboard", "Logitech K120")
    return i


def test_assign_and_return_with_history(inv, tmp_path):
    inv.assign("LT-0001", "asha.k", "HD-101")
    inv.assign("MN-0001", "asha.k", "HD-101")
    assert [i.asset_tag for i in inv.assigned_to("asha.k")] == ["LT-0001", "MN-0001"]
    inv.return_item("MN-0001", "HD-150", "damaged")
    assert inv.get("MN-0001").status == "repair"
    inv.save()
    reloaded = Inventory(tmp_path / "equipment.csv")
    assert reloaded.get("LT-0001").assigned_to == "asha.k"
    history = (tmp_path / "history.csv").read_text().splitlines()
    assert history[0] == "timestamp,action,asset_tag,user,ticket,note"
    assert any(",return,MN-0001,asha.k,HD-150,damaged" in line for line in history)


def test_cannot_assign_twice_or_add_duplicates(inv):
    inv.assign("LT-0001", "asha.k", "HD-101")
    with pytest.raises(InventoryError, match="assigned to asha.k"):
        inv.assign("LT-0001", "ben.t", "HD-102")
    with pytest.raises(InventoryError, match="already exists"):
        inv.add("LT-0001", "laptop", "x")
    with pytest.raises(InventoryError, match="Serial SN2"):
        inv.add("LT-0009", "laptop", "x", "SN2")
    with pytest.raises(InventoryError, match="Unknown type"):
        inv.add("XX-1", "toaster", "x")
    with pytest.raises(ValueError):
        inv.add("LT-0010", "laptop", "x", warranty_end="2027-13-01")


def test_report_warranty_and_stock(inv):
    inv.assign("LT-0002", "ben.t", "HD-102")
    r = inv.report(today=date(2026, 11, 23), warranty_days=90)
    assert r["warranty_expiring"] == ["LT-0001"]
    assert r["warranty_expired"] == ["MN-0001"]
    assert r["laptops_in_stock"] == 1
    assert r["by_status"] == {"in-stock": 3, "assigned": 1}


def test_cli(tmp_path, capsys):
    db = str(tmp_path / "e.csv")
    assert main(["--db", db, "add", "LT-1", "laptop", "ThinkPad T14", "--warranty", "2028-01-01"]) == 0
    assert main(["--db", db, "assign", "LT-1", "asha.k", "--ticket", "HD-1"]) == 0
    assert main(["--db", db, "assign", "LT-1", "ben.t", "--ticket", "HD-2"]) == 1
    assert "Laptops in stock for new hires: 0" in (main(["--db", db, "report"]) or capsys.readouterr().out)
