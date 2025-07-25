import pandas as pd
import json
from collections import defaultdict

# === File paths ===
nodes_csv = "data/domain_nodes.csv"
edges_csv = "data/domain_dependencies.csv"
nodes_out = "data/nodes.json"
edges_out = "data/links.json"

# === Tier group to x-axis mapping ===
x_group_map = {
    "Foundational": 0,
    "Tier 1 Dependency": 1,
    "Tier 2 Dependency": 2,
    "Compilatory": 3,
    "Resulting": 4  # Updated to allow full rightmost placement
}

# === Utility: Line-wrap long labels ===
def wrap_label(text, max_len=22):
    words, lines, line = text.split(), [], ""
    for word in words:
        if len(line + " " + word) > max_len:
            lines.append(line)
            line = word
        else:
            line += (" " + word) if line else word
    if line:
        lines.append(line)
    return "\n".join(lines)

# === Convert domain nodes ===
def convert_nodes():
    df = pd.read_csv(nodes_csv)

    # Map tier groups to X axis, maturity to Y
    df["X"] = df["TIER_GROUP"].map(x_group_map).fillna(0).astype(int)
    df["Y"] = df["CURRENT_MATURITY"].astype(float)

    # Prepare base node objects
    node_json = []
    for _, row in df.iterrows():
        node_json.append({
            "id": row["DOMAIN_ID"],
            "name": row["DOMAIN_NAME"],
            "x": row["X"],
            "y": row["Y"],
            "group": row["TIER_GROUP"],
            "color": row.get("COLOR_HEX", "#f0f0f0"),
            "border": row.get("BORDER_HEX", "#333"),
            "label": wrap_label(row["DOMAIN_NAME"])
        })

    # Apply Y-jitter for overlapping nodes in same (x, y)
    grouped = defaultdict(list)
    for node in node_json:
        grouped[(node["x"], node["y"])].append(node)

    for (x, y), group in grouped.items():
        if len(group) > 1:
            spacing = 0.23
            for i, node in enumerate(group):
                node["y"] = round(y + (i - (len(group)-1)/2) * spacing, 3)

    # Save to JSON
    with open(nodes_out, "w") as f:
        json.dump(node_json, f, indent=2)
    print(f"✅ Wrote {len(node_json)} nodes to {nodes_out}")

# === Convert domain dependency edges ===
def convert_edges():
    df = pd.read_csv(edges_csv, encoding="ISO-8859-1")

    edge_json = []
    for _, row in df.iterrows():
        edge_json.append({
            "source": row["SOURCE_DOMAIN_ID"],
            "target": row["TARGET_DOMAIN_ID"]
        })

    with open(edges_out, "w") as f:
        json.dump(edge_json, f, indent=2)
    print(f"✅ Wrote {len(edge_json)} links to {edges_out}")

# === Run conversion ===
if __name__ == "__main__":
    convert_nodes()
    convert_edges()
