#!/usr/bin/env python3

import argparse
import pandas as pd
from collections import defaultdict
from pathlib import Path


# -----------------------------
# Parse Kraken taxonomy files
# -----------------------------
def load_taxonomy(taxonomy_dir):
    nodes_file = Path(taxonomy_dir) / "nodes.dmp"
    names_file = Path(taxonomy_dir) / "names.dmp"

    parent = {}
    rank = {}
    names = {}

    # Parse nodes.dmp
    with open(nodes_file) as f:
        for line in f:
            parts = [x.strip() for x in line.split("|")]
            tax_id = parts[0]
            parent_id = parts[1]
            tax_rank = parts[2]
            parent[tax_id] = parent_id
            rank[tax_id] = tax_rank

    # Parse names.dmp
    with open(names_file) as f:
        for line in f:
            parts = [x.strip() for x in line.split("|")]
            tax_id = parts[0]
            name_txt = parts[1]
            name_class = parts[3]
            if name_class == "scientific name":
                names[tax_id] = name_txt

    return parent, rank, names


# -----------------------------
# Get lineage for a taxid
# -----------------------------
def get_lineage(tax_id, parent, rank, names, wanted_ranks):
    lineage = {}
    current = tax_id

    while current in parent and current != parent[current]:
        r = rank.get(current)
        if r in wanted_ranks:
            lineage[r] = names.get(current, current)
        current = parent[current]

    return lineage


# -----------------------------
# Main
# -----------------------------
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bracken", required=True)
    parser.add_argument("--taxonomy", required=True)
    parser.add_argument("--min_count", type=int, default=0)
    parser.add_argument("--output_prefix", default="sankey")
    args = parser.parse_args()

    wanted_ranks = [
        "superkingdom",
        "phylum",
        "class",
        "order",
        "family",
        "genus",
        "species",
    ]

    print("Loading taxonomy...")
    parent, rank, names = load_taxonomy(args.taxonomy)

    print("Reading Bracken file...")
    df = pd.read_csv(args.bracken, sep="\t")

    # Identify count columns: prefer _num columns (multi-sample), fall back to new_est_reads (single sample)
    count_cols = [c for c in df.columns if c.endswith("_num")]
    if not count_cols:
        # Single-sample bracken output: use new_est_reads
        count_cols = ["new_est_reads"] if "new_est_reads" in df.columns else []
    
    if not count_cols:
        print("ERROR: No count columns found. Expected '_num' columns or 'new_est_reads'")
        return

    # Convert counts to numeric
    for col in count_cols:
        df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0).astype(int)

    # Aggregate all count columns into a single combined output
    print(f"Creating combined Sankey using count columns: {count_cols}")
    
    edges_combined = defaultdict(int)

    for _, row in df.iterrows():
        # Sum counts across all samples for this taxon
        total_count = sum(row[col] for col in count_cols)

        if total_count < args.min_count:
            continue

        tax_id = str(row["taxonomy_id"])

        lineage = get_lineage(tax_id, parent, rank, names, wanted_ranks)

        # Order lineage by rank
        ordered = []
        for r in wanted_ranks:
            if r in lineage:
                ordered.append(f"{r.capitalize()}: {lineage[r]}")

        # Build edges
        for i in range(len(ordered) - 1):
            source = ordered[i]
            target = ordered[i + 1]
            edges_combined[(source, target)] += total_count

    # Write combined output
    output_file = f"{args.output_prefix}.plot_data.csv"
    with open(output_file, "w") as out:
        out.write("source,target,value\n")
        for (s, t), v in edges_combined.items():
            out.write(f"{s},{t},{v}\n")

    print(f"Written {output_file}")


if __name__ == "__main__":
    main()
