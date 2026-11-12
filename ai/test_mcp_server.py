"""Tests for the offline, read-only ArchiBIM MCP JSON-RPC bridge."""
import json
import tempfile
import unittest
from pathlib import Path

import mcp_server as bridge


class ReadonlyMcpTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "model.json"
        self.path.write_text(json.dumps({
            "schema_version": "1.0", "version": "0.8.0",
            "units": "mm", "levels": [{"id": "GF", "name": "Ground", "elevation": 0}],
            "elements": [{"id": "w-1", "kind": "wall", "level_id": "GF", "thickness": 150}],
            "drawings": [{"key": "ground", "name": "A-101"}],
        }), encoding="utf-8")

    def tearDown(self):
        self.tmp.cleanup()

    def test_tools_discovery(self):
        r = bridge.handle({"jsonrpc": "2.0", "id": 1, "method": "tools/list"}, self.path)
        self.assertGreaterEqual(len(r["result"]["tools"]), 5)

    def test_model_read(self):
        r = bridge.handle({"jsonrpc": "2.0", "id": "a", "method": "tools/call",
                           "params": {"name": "archibim_get_element", "arguments": {"id": "w-1"}}},
                          self.path)
        data = json.loads(r["result"]["content"][0]["text"])
        self.assertEqual(150, data["thickness"])

    def test_notification_no_reply(self):
        self.assertIsNone(bridge.handle({"jsonrpc": "2.0", "method": "notifications/initialized"}, self.path))

    def test_read_only_tools(self):
        self.assertFalse(any("write" in t["name"] or "delete" in t["name"]
                             for t in bridge.TOOLS))
        with self.assertRaises(ValueError):
            bridge.call_tool("archibim_get_element", {"id": "w-1", "inject": True}, self.path)


if __name__ == "__main__":
    unittest.main()
