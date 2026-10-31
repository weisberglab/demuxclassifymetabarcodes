import argparse
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.path import Path
import matplotlib.patches as patches
import numpy as np
import plotly.graph_objects as go


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--db_name", required=True)
    p.add_argument("--run_name", required=True)
    p.add_argument("--input", default=None, help="Override input CSV path")
    return p.parse_args()

args = parse_args()
input_file = args.input if args.input else f"{args.run_name}.{args.db_name}.plot_data.csv"

# Read the data
df = pd.read_csv(input_file)

# Get unique nodes and sort them by rank (columns left to right)
all_nodes = list(set(df['source'].tolist() + df['target'].tolist()))
rank_order = ['superkingdom', 'phylum', 'class', 'order', 'family', 'genus', 'species']

def get_rank(node):
    for i, rank in enumerate(rank_order):
        if rank.capitalize() in node:
            return i
    return len(rank_order)

all_nodes_sorted = sorted(all_nodes, key=get_rank)
node_indices = {node: i for i, node in enumerate(all_nodes_sorted)}

# Group nodes by rank for positioning
node_positions = {}
rank_groups = {}
for node in all_nodes_sorted:
    rank = get_rank(node)
    if rank not in rank_groups:
        rank_groups[rank] = []
    rank_groups[rank].append(node)

# Assign y positions
y_pos = 0
for rank in sorted(rank_groups.keys()):
    nodes = rank_groups[rank]
    for i, node in enumerate(nodes):
        node_positions[node] = (rank, i)
    y_pos = max([node_positions[n][1] for n in nodes]) + 1

# Create figure
fig, ax = plt.subplots(figsize=(14, 10))
ax.set_xlim(-0.5, len(rank_order) + 0.5)
ax.set_ylim(-1, y_pos + 1)
ax.axis('off')

# Draw flows
for _, row in df.iterrows():
    src = row['source']
    tgt = row['target']
    val = row['value']
    
    x1, y1 = node_positions[src]
    x2, y2 = node_positions[tgt]
    
    # Normalize flow width
    width = max(0.5, val / df['value'].max() * 3)
    ax.plot([x1, x2], [y1, y2], alpha=0.3, linewidth=width, color='steelblue')

# Draw nodes
for node, (x, y) in node_positions.items():
    ax.scatter(x, y, s=200, color='darkblue', zorder=3)
    ax.text(x + 0.1, y, node, fontsize=8, va='center')

plt.title("Taxonomic Distribution", fontsize=14, fontweight='bold')
plt.tight_layout()

# Create interactive HTML with Plotly
all_nodes_set = list(set(df['source'].tolist() + df['target'].tolist()))
source_indices = [all_nodes_set.index(src) for src in df['source']]
target_indices = [all_nodes_set.index(tgt) for tgt in df['target']]

fig_html = go.Figure(data=[go.Sankey(
    node=dict(
        pad=15,
        thickness=20,
        line=dict(color='black', width=0.5),
        label=all_nodes_set
    ),
    link=dict(
        source=source_indices,
        target=target_indices,
        value=df['value'].tolist()
    )
)])

fig_html.update_layout(
    title=f"Taxonomic Distribution for {args.run_name} with database {args.db_name}",
    font=dict(size=10),
    height=700
)

fig_html.write_html(f'{args.run_name}.{args.db_name}.sankey_plot.html')