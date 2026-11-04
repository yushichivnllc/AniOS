#!/usr/bin/env python3
"""Rewrite and verify a libvirt domain's network interfaces for Anix."""
from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NETWORKS = {
    "gateway": ["anix-wan", "anix-internal"],
    "workstation": ["anix-internal"],
}
PRESERVED = ("mac", "target", "model", "driver", "link", "alias", "address")
LATER_DEVICE_TAGS = {
    "serial", "parallel", "console", "channel", "input", "hub", "graphics",
    "sound", "audio", "video", "hostdev", "redirdev", "memballoon", "rng",
    "panic", "shmem",
}


def rewrite(source: Path, target: Path, role: str) -> None:
    root = ET.parse(source).getroot()
    devices = root.find("devices")
    if devices is None:
        raise ValueError("VM definition has no <devices> section")

    old_interfaces = list(devices.findall("interface"))
    for old in old_interfaces:
        devices.remove(old)

    for index, network in enumerate(NETWORKS[role]):
        old = old_interfaces[index] if index < len(old_interfaces) else None
        old_children = {tag: old.find(tag) for tag in PRESERVED} if old is not None else {}
        interface = ET.Element("interface", {"type": "network"})
        if old_children.get("mac") is not None:
            interface.append(old_children["mac"])
        ET.SubElement(interface, "source", {"network": network})
        for tag in PRESERVED[1:]:
            if old_children.get(tag) is not None:
                interface.append(old_children[tag])

        # Keep libvirt's usual device ordering: interfaces precede serial,
        # graphics, video and host devices, while retaining unrelated devices.
        later = next((child for child in devices if child.tag in LATER_DEVICE_TAGS), None)
        if later is None:
            devices.append(interface)
        else:
            devices.insert(list(devices).index(later), interface)

    target.write_text(ET.tostring(root, encoding="unicode", xml_declaration=True) + "\n")


def verify(source: Path, role: str) -> None:
    root = ET.parse(source).getroot()
    nodes = root.findall("./devices/interface")
    actual: list[str] = []
    for node in nodes:
        source_node = node.find("source")
        if node.get("type") != "network" or source_node is None:
            actual.append(f"<unsafe:{node.get('type', 'unknown')}>")
        else:
            actual.append(source_node.get("network", ""))
    expected = NETWORKS[role]
    if actual != expected:
        raise ValueError(f"network isolation mismatch: expected {expected}, got {actual}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    rewrite_parser = sub.add_parser("rewrite")
    rewrite_parser.add_argument("source", type=Path)
    rewrite_parser.add_argument("target", type=Path)
    rewrite_parser.add_argument("role", choices=NETWORKS)
    verify_parser = sub.add_parser("verify")
    verify_parser.add_argument("source", type=Path)
    verify_parser.add_argument("role", choices=NETWORKS)
    args = parser.parse_args()
    try:
        if args.action == "rewrite":
            rewrite(args.source, args.target, args.role)
        else:
            verify(args.source, args.role)
    except (ET.ParseError, OSError, ValueError) as error:
        print(f"Anix: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
