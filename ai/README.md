# ArchiBIM for ChatGPT, Claude, Gemini and other MCP clients

ArchiBIM offers two **read-only** ways to interpret BIM data without requiring an AI model to understand SketchUp's native `.skp` format.

## Option 1: ChatGPT upload (easiest)

In SketchUp Desktop, open **Extensions > ArchiBIM > BIM Manager > Export > Export AI-readable JSON**. Save `ArchiBIM_AI.json`, attach it in ChatGPT and ask e.g. "List all ground floor walls, dimensions and hosted doors", "Check my roof truss spacing", or "Summarize the A-101 to A-402 drawing scenes".

The export contains model and level names, element IDs/kinds/parameters, world origins in mm, drawing labels and limitations. It is a snapshot. When the model changes, export again to refresh the data. No user data is transmitted by the plugin.

Schema: [archibim-snapshot.schema.json](archibim-snapshot.schema.json).

## Option 2: Local Model Context Protocol (MCP)

This repository includes a lightweight **MCP stdio server** for clients that can configure local MCP processes. It uses standard-library Python 3.10+ only; there are no model writes, tokens, subprocesses, network listeners or remote API requests. It reads only a user-selected snapshot path.

### Start it manually

```powershell
python ai/mcp_server.py --snapshot "C:\\Users\\User\\Documents\\ArchiBIM_AI.json"
```

For an MCP client, configure a stdio command with `python`, arguments `/absolute/path/to/ArchiBIM/ai/mcp_server.py`, `--snapshot`, and your exported `ArchiBIM_AI.json` absolute path.

Sample client config (adjust executable and paths):

```json
{
  "mcpServers": {
    "archibim-readonly": {
      "command": "python",
      "args": [
        "C:/ArchiBIM/ai/mcp_server.py",
        "--snapshot",
        "C:/Users/User/Documents/ArchiBIM_AI.json"
      ]
    }
  }
}
```

The server exposes the following read-only tools: `archibim_model_summary`, `archibim_list_levels`, `archibim_list_elements`, `archibim_get_element` and `archibim_list_drawings`.

ChatGPT's external connector / custom MCP support is plan- and deployment-dependent, so the **JSON upload is the broadly compatible default**. This server is not a public ChatGPT Plugin Directory integration and has no live SketchUp connection.

## Design and security rules

- Keep the `.skp` model and snapshot on your computer unless you choose to share them.
- A selected JSON file is the *only* model data source. Edits requested by any model do not change SketchUp.
- Avoid handing arbitrary filesystem paths to an AI command. The server is intentionally pinned to one `--snapshot`.
- Confirm units before dimensional interpretation. Snapshots use millimetres; cost rates are illustrative.
- Existing elements are not automatically inferred into structural safety assessments; steel trusses/awnings are conceptual.
- A future live adapter must use explicit user authorization, whitelisted atomic SketchUp operations, SketchUp Undo, and logs. Do not expose a local server to the public internet.

[Research and future live-MCP plan](../docs/RESEARCH_DRAWINGS_ROOFS_MCP.md).
