#!/usr/bin/env python3
"""Read-only Model Context Protocol (MCP) stdio server for ArchiBIM snapshots.

Usage: python3 ai/mcp_server.py --snapshot /path/to/ArchiBIM_AI.json
No dependencies, server sockets, uploads, or model writes.
"""
from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path

SCHEMA = "2025-11-25"
MAX_SNAPSHOT_BYTES = 20 * 1024 * 1024

TOOLS = [
    {
        "name": "archibim_model_summary",
        "description": "Summarize the offline exported ArchiBIM model and the number of elements, stories and generated drawings.",
        "inputSchema": {"type": "object", "additionalProperties": False},
    },
    {
        "name": "archibim_list_levels",
        "description": "List story IDs, names, and absolute level elevations in millimetres.",
        "inputSchema": {"type": "object", "additionalProperties": False},
    },
    {
        "name": "archibim_list_elements",
        "description": "List model BIM objects, with an optional element kind filter, based only on the exported snapshot.",
        "inputSchema": {
            "type": "object",
            "properties": {"kind": {"type": "string"}},
            "additionalProperties": False,
        },
    },
    {
        "name": "archibim_get_element",
        "description": "Get one element and its stored geometry parameters using its stable ArchiBIM ID.",
        "inputSchema": {
            "type": "object",
            "properties": {"id": {"type": "string", "minLength": 1}},
            "required": ["id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "archibim_list_drawings",
        "description": "List generated SketchUp drawing scenes and their reference codes.",
        "inputSchema": {"type": "object", "additionalProperties": False},
    },
]


def snapshot(path: Path) -> dict:
    if not path.is_file() or path.stat().st_size > MAX_SNAPSHOT_BYTES:
        raise ValueError("Snapshot missing or too large (limit 20 MiB)")
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or data.get("schema_version") != "1.0":
        raise ValueError("Use a valid ArchiBIM schema_version 1.0 JSON export")
    if not isinstance(data.get("elements"), list) or not isinstance(data.get("levels"), list):
        raise ValueError("Invalid elements or levels")
    return data


def call_tool(name: str, args: dict, path: Path):
    if not isinstance(args, dict):
        raise ValueError("Arguments must be a JSON object")
    tool = next((tool for tool in TOOLS if tool["name"] == name), None)
    if tool is None:
        raise ValueError("Unknown tool")
    allowed = set(tool["inputSchema"].get("properties", {}))
    if set(args) - allowed:
        raise ValueError("Unexpected tool argument")
    data = snapshot(path)
    if name == "archibim_model_summary":
        return {"model_title": data.get("model_title", ""),
                "version": data.get("version", ""),
                "units": data.get("units", ""),
                "levels": len(data["levels"]),
                "elements": len(data["elements"]),
                "drawings": len(data.get("drawings", [])),
                "warnings": data.get("warnings", [])}
    if name == "archibim_list_levels":
        return data["levels"]
    if name == "archibim_list_drawings":
        return data.get("drawings", [])
    if name == "archibim_list_elements":
        kind = args.get("kind")
        filtered = [e for e in data["elements"] if kind is None or e.get("kind") == kind]
        return [{"id": e.get("id"), "kind": e.get("kind"),
                 "name": e.get("name"), "level_id": e.get("level_id")}
                for e in filtered[:2000]]
    if name == "archibim_get_element":
        element_id = args.get("id")
        if not isinstance(element_id, str) or not element_id:
            raise ValueError("id must be a nonempty string")
        return next((e for e in data["elements"] if e.get("id") == element_id), None)
    raise ValueError("Unknown tool")


def handle(message: dict, path: Path) -> dict | None:
    if not isinstance(message, dict) or message.get("jsonrpc") != "2.0":
        raise ValueError("Expected JSON-RPC 2.0")
    method = message.get("method")
    if "id" not in message:
        return None  # MCP notifications never receive a response.
    req_id = message["id"]
    params = message.get("params") or {}
    if not isinstance(params, dict):
        raise ValueError("params must be an object")
    if method == "initialize":
        version = params.get("protocolVersion", SCHEMA)
        result = {"protocolVersion": version, "capabilities": {"tools": {}},
                  "serverInfo": {"name": "archibim-readonly", "version": "0.1.0"}}
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        result = {"tools": TOOLS}
    elif method == "tools/call":
        value = call_tool(params.get("name"), params.get("arguments", {}), path)
        result = {"content": [{"type": "text", "text": json.dumps(value, ensure_ascii=False)}]}
    else:
        return {"jsonrpc": "2.0", "id": req_id,
                "error": {"code": -32601, "message": "Method not found"}}
    return {"jsonrpc": "2.0", "id": req_id, "result": result}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--snapshot", type=Path, required=True)
    path = parser.parse_args().snapshot.expanduser().resolve()
    for line in sys.stdin:
        try:
            message = json.loads(line)
            reply = handle(message, path)
            if reply is not None:
                sys.stdout.write(json.dumps(reply, ensure_ascii=False) + "\n")
                sys.stdout.flush()
        except (ValueError, TypeError, KeyError, OSError, json.JSONDecodeError) as exc:
            request_id = message.get("id") if isinstance(locals().get("message"), dict) else None
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": request_id,
                "error": {"code": -32602, "message": str(exc)}}) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
