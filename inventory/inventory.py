"""IT equipment inventory: track laptops, monitors and peripherals, who has them, and warranty dates.

Usage:
  python inventory/inventory.py add LT-0042 laptop "Dell Latitude 5440" --serial 7XK21 --warranty 2028-03-31
  python inventory/inventory.py assign LT-0042 asha.k --ticket HD-101
  python inventory/inventory.py return LT-0042 --ticket HD-150 --condition good
  python inventory/inventory.py report [--warranty-days 90]
"""
from __future__ import annotations

import argparse
import csv
import sys
from dataclasses import asdict, dataclass, fields
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

DEFAULT_DB = Path(__file__).with_name("equipment.csv")
HISTORY = "history.csv"
TYPES = {"laptop", "desktop", "monitor", "dock", "keyboard", "mouse", "headset", "phone", "printer", "other"}


@dataclass
class Item:
    asset_tag: str
    type: str
    model: str
    serial: str = ""
    status: str = "in-stock"  # in-stock | assigned | repair | retired
    assigned_to: str = ""
    warranty_end: str = ""  # YYYY-MM-DD
    condition: str = "good"


class InventoryError(Exception):
    pass


class Inventory:
    def __init__(self, path: Path = DEFAULT_DB):
        self.path = Path(path)
        self.items: dict[str, Item] = {}
        if self.path.exists():
            with self.path.open(newline="") as f:
                for row in csv.DictReader(f):
                    self.items[row["asset_tag"]] = Item(**row)

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.path.open("w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=[fl.name for fl in fields(Item)])
            w.writeheader()
            for item in sorted(self.items.values(), key=lambda i: i.asset_tag):
                w.writerow(asdict(item))

    def _log(self, action: str, tag: str, user: str, ticket: str, note: str = "") -> None:
        hist = self.path.with_name(HISTORY)
        new = not hist.exists()
        with hist.open("a", newline="") as f:
            w = csv.writer(f)
            if new:
                w.writerow(["timestamp", "action", "asset_tag", "user", "ticket", "note"])
            w.writerow([datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), action, tag, user, ticket, note])

    def get(self, tag: str) -> Item:
        if tag not in self.items:
            raise InventoryError(f"No equipment with asset tag {tag}")
        return self.items[tag]

    def add(self, tag: str, type_: str, model: str, serial: str = "", warranty_end: str = "") -> Item:
        if tag in self.items:
            raise InventoryError(f"Asset tag {tag} already exists")
        if type_ not in TYPES:
            raise InventoryError(f"Unknown type {type_}; use one of {', '.join(sorted(TYPES))}")
        if warranty_end:
            date.fromisoformat(warranty_end)  # raises ValueError for a bad date
        if serial and any(i.serial == serial for i in self.items.values()):
            raise InventoryError(f"Serial {serial} is already recorded")
        item = Item(tag, type_, model, serial, warranty_end=warranty_end)
        self.items[tag] = item
        self._log("add", tag, "", "", model)
        return item

    def assign(self, tag: str, user: str, ticket: str) -> Item:
        item = self.get(tag)
        if item.status != "in-stock":
            raise InventoryError(f"{tag} is {item.status}" + (f" to {item.assigned_to}" if item.assigned_to else "") + "; return it first")
        item.status, item.assigned_to = "assigned", user
        self._log("assign", tag, user, ticket)
        return item

    def return_item(self, tag: str, ticket: str, condition: str = "good") -> Item:
        item = self.get(tag)
        if item.status != "assigned":
            raise InventoryError(f"{tag} is not assigned")
        user = item.assigned_to
        item.assigned_to, item.condition = "", condition
        item.status = "in-stock" if condition == "good" else "repair"
        self._log("return", tag, user, ticket, condition)
        return item

    def assigned_to(self, user: str) -> list[Item]:
        """Everything a person has: used in offboarding to collect equipment."""
        return [i for i in self.items.values() if i.assigned_to == user]

    def report(self, today: date | None = None, warranty_days: int = 90) -> dict:
        today = today or date.today()
        soon = today + timedelta(days=warranty_days)
        by_status: dict[str, int] = {}
        for i in self.items.values():
            by_status[i.status] = by_status.get(i.status, 0) + 1
        expiring = [i.asset_tag for i in self.items.values()
                    if i.warranty_end and today <= date.fromisoformat(i.warranty_end) <= soon and i.status != "retired"]
        expired = [i.asset_tag for i in self.items.values()
                   if i.warranty_end and date.fromisoformat(i.warranty_end) < today and i.status != "retired"]
        laptops_in_stock = sum(1 for i in self.items.values() if i.type == "laptop" and i.status == "in-stock")
        return {"total": len(self.items), "by_status": by_status, "warranty_expiring": sorted(expiring),
                "warranty_expired": sorted(expired), "laptops_in_stock": laptops_in_stock}


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--db", default=str(DEFAULT_DB))
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("add"); a.add_argument("tag"); a.add_argument("type"); a.add_argument("model")
    a.add_argument("--serial", default=""); a.add_argument("--warranty", default="")
    s = sub.add_parser("assign"); s.add_argument("tag"); s.add_argument("user"); s.add_argument("--ticket", required=True)
    r = sub.add_parser("return"); r.add_argument("tag"); r.add_argument("--ticket", required=True)
    r.add_argument("--condition", default="good", choices=["good", "damaged"])
    u = sub.add_parser("user"); u.add_argument("user")
    rep = sub.add_parser("report"); rep.add_argument("--warranty-days", type=int, default=90)
    args = p.parse_args(argv)
    inv = Inventory(Path(args.db))
    try:
        if args.cmd == "add":
            item = inv.add(args.tag, args.type, args.model, args.serial, args.warranty); inv.save(); print(f"Added {item.asset_tag} ({item.model})")
        elif args.cmd == "assign":
            item = inv.assign(args.tag, args.user, args.ticket); inv.save(); print(f"Assigned {item.asset_tag} to {item.assigned_to}")
        elif args.cmd == "return":
            item = inv.return_item(args.tag, args.ticket, args.condition); inv.save(); print(f"Returned {item.asset_tag}: now {item.status}")
        elif args.cmd == "user":
            items = inv.assigned_to(args.user)
            print("\n".join(f"{i.asset_tag}  {i.type:8} {i.model}" for i in items) or f"No equipment assigned to {args.user}")
        else:
            r = inv.report(warranty_days=args.warranty_days)
            print(f"Equipment: {r['total']} ({', '.join(f'{k}: {v}' for k, v in sorted(r['by_status'].items()))})")
            print(f"Laptops in stock for new hires: {r['laptops_in_stock']}")
            print(f"Warranty ending within {args.warranty_days} days: {', '.join(r['warranty_expiring']) or 'none'}")
            print(f"Warranty expired: {', '.join(r['warranty_expired']) or 'none'}")
    except (InventoryError, ValueError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
