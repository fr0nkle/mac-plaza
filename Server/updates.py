"""Authenticated, local release hosting. No GitHub token is sent to clients."""
import base64
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET


class ReleaseStore:
    def __init__(self, root):
        self.root = Path(root).resolve()

    def manifest(self):
        manifest = json.loads((self.root / "release.json").read_text())
        for key in ("version", "build"):
            if not isinstance(manifest[key], str) or not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", manifest[key]):
                raise ValueError("Invalid release version")
        if len(base64.b64decode(manifest["signature"], validate=True)) != 64:
            raise ValueError("Invalid update signature")
        archive = self.asset(manifest["archive"])
        if archive.stat().st_size != manifest["length"]:
            raise ValueError("Incomplete release archive")
        return manifest

    def asset(self, name):
        if not isinstance(name, str) or not re.fullmatch(r"Mac-Plaza-[0-9.]+(?:-Source)?\.zip", name):
            raise ValueError("Invalid release archive")
        path = (self.root / name).resolve()
        if path.parent != self.root or not path.is_file():
            raise ValueError("Unavailable release archive")
        return path

    def appcast(self, origin):
        ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
        ET.register_namespace("sparkle", ns)
        rss = ET.Element("rss", version="2.0")
        channel = ET.SubElement(rss, "channel")
        ET.SubElement(channel, "title").text = "Mac Plaza private testing"
        manifest = self.manifest()
        item = ET.SubElement(channel, "item")
        ET.SubElement(item, "title").text = "Mac Plaza " + manifest["version"]
        ET.SubElement(item, "description").text = manifest.get("notes", "Mac Plaza testing update.")[:4000]
        ET.SubElement(item, "{" + ns + "}minimumSystemVersion").text = "15.0"
        ET.SubElement(item, "enclosure", {
            "url": origin + "/updates/" + manifest["archive"], "length": str(manifest["length"]),
            "type": "application/octet-stream", "{" + ns + "}version": manifest["build"],
            "{" + ns + "}shortVersionString": manifest["version"], "{" + ns + "}edSignature": manifest["signature"]})
        return ET.tostring(rss, encoding="utf-8", xml_declaration=True)
