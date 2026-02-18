#!/usr/bin/env python3
"""
M. leprae Drug Resistance Mutation Analyzer
============================================
Screens annotated VCF files for known drug resistance mutations.

Supported drug classes:
  - Rifampicin     (rpoB)
  - Dapsone        (folP1)
  - Fluoroquinolones (gyrA / gyrB)

Usage:
  python3 analyze_drug_resistance.py <annotated.vcf> [-o output.tsv] [-r report.txt]

References:
  - WHO Guidelines for Leprosy (2018)
  - Benjak et al. (2018) - Phylogenomics and AMR of M. leprae
  - Cambau & Drancourt (2014) - Drug resistance in leprosy
  - Matsuoka et al. (2007) - Drug resistance in leprosy
"""

import argparse
import sys
from datetime import datetime

# ---------------------------------------------------------------------------
# Known drug resistance mutation database
# ---------------------------------------------------------------------------
RESISTANCE_DB = {
    "rpoB": {
        "drug": "Rifampicin",
        "class": "Rifamycin",
        "mutations": {
            "S425L": "High",
            "S425F": "High",
            "D441Y": "High",
            "D441V": "High",
            "H451Y": "High",
            "H451D": "High",
            "S456L": "High",
            "Q432R": "Moderate",
            "Q432K": "Moderate",
        },
    },
    "folP1": {
        "drug": "Dapsone",
        "class": "Sulfone",
        "mutations": {
            "T53I": "High",
            "T53A": "High",
            "P55L": "High",
            "P55R": "High",
            "P55S": "High",
            "P55T": "Moderate",
        },
    },
    "gyrA": {
        "drug": "Ofloxacin / Fluoroquinolones",
        "class": "Fluoroquinolone",
        "mutations": {
            "A91V": "High",
            "A91T": "High",
            "D95N": "High",
            "D95Y": "High",
            "D95G": "High",
        },
    },
    "gyrB": {
        "drug": "Ofloxacin / Fluoroquinolones",
        "class": "Fluoroquinolone",
        "mutations": {
            "R447C": "Moderate",
            "G447D": "Moderate",
        },
    },
}


# ---------------------------------------------------------------------------
# VCF parsing helpers
# ---------------------------------------------------------------------------

def parse_vcf(vcf_path: str) -> list[dict]:
    """Parse a SnpEff-annotated VCF and return a list of variant records."""
    variants = []
    samples = []

    with open(vcf_path) as fh:
        for line in fh:
            line = line.rstrip()

            if line.startswith("##"):
                continue

            if line.startswith("#CHROM"):
                fields = line.lstrip("#").split("\t")
                # Columns after FORMAT are sample names
                if len(fields) > 9:
                    samples = fields[9:]
                continue

            cols = line.split("\t")
            if len(cols) < 8:
                continue

            chrom, pos, var_id, ref, alt, qual, filt, info = cols[:8]
            fmt_keys = cols[8].split(":") if len(cols) > 8 else []
            sample_data = cols[9:] if len(cols) > 9 else []

            # Parse ANN field from INFO
            ann_entries = []
            for token in info.split(";"):
                if token.startswith("ANN="):
                    raw_anns = token[4:].split(",")
                    for ann in raw_anns:
                        parts = ann.split("|")
                        if len(parts) >= 10:
                            ann_entries.append(
                                {
                                    "allele": parts[0],
                                    "effect": parts[1],
                                    "impact": parts[2],
                                    "gene_name": parts[3],
                                    "gene_id": parts[4],
                                    "biotype": parts[7],
                                    "aa_change": parts[10] if len(parts) > 10 else "",
                                }
                            )

            # Parse per-sample genotypes
            gt_map = {}
            for i, sname in enumerate(samples):
                if i < len(sample_data):
                    vals = sample_data[i].split(":")
                    gt_map[sname] = dict(zip(fmt_keys, vals))

            variants.append(
                {
                    "chrom": chrom,
                    "pos": int(pos),
                    "id": var_id,
                    "ref": ref,
                    "alt": alt,
                    "qual": qual,
                    "filter": filt,
                    "annotations": ann_entries,
                    "genotypes": gt_map,
                }
            )

    return variants, samples


def check_resistance(variant: dict) -> list[dict]:
    """Return a list of resistance hits for a variant."""
    hits = []

    for ann in variant["annotations"]:
        gene = ann["gene_name"]
        aa = ann["aa_change"].replace("p.", "") if ann["aa_change"] else ""

        if gene not in RESISTANCE_DB:
            continue

        gene_info = RESISTANCE_DB[gene]

        for mut, level in gene_info["mutations"].items():
            # Match by amino-acid change (e.g. S425L)
            if mut in aa:
                hits.append(
                    {
                        "gene": gene,
                        "drug": gene_info["drug"],
                        "drug_class": gene_info["class"],
                        "mutation": mut,
                        "aa_change": aa,
                        "effect": ann["effect"],
                        "resistance_level": level,
                        "chrom": variant["chrom"],
                        "pos": variant["pos"],
                        "ref": variant["ref"],
                        "alt": variant["alt"],
                        "genotypes": variant["genotypes"],
                    }
                )

    return hits


# ---------------------------------------------------------------------------
# Report writers
# ---------------------------------------------------------------------------

def write_tsv(hits: list[dict], samples: list[str], out_path: str):
    """Write a tab-separated mutations table."""
    header = [
        "Gene", "Drug", "Drug_Class", "Mutation", "AA_Change",
        "Effect", "Resistance_Level", "CHROM", "POS", "REF", "ALT",
    ] + [f"GT_{s}" for s in samples]

    with open(out_path, "w") as fh:
        fh.write("\t".join(header) + "\n")
        for h in hits:
            row = [
                h["gene"], h["drug"], h["drug_class"],
                h["mutation"], h["aa_change"], h["effect"],
                h["resistance_level"], h["chrom"], str(h["pos"]),
                h["ref"], h["alt"],
            ]
            for s in samples:
                gt = h["genotypes"].get(s, {}).get("GT", ".")
                row.append(gt)
            fh.write("\t".join(row) + "\n")


def write_report(hits: list[dict], samples: list[str], vcf_path: str, report_path: str):
    """Write a human-readable resistance summary report."""
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    with open(report_path, "w") as fh:
        fh.write("=" * 80 + "\n")
        fh.write("M. LEPRAE DRUG RESISTANCE ANALYSIS REPORT\n")
        fh.write("=" * 80 + "\n")
        fh.write(f"Generated : {now}\n")
        fh.write(f"Input VCF : {vcf_path}\n")
        fh.write(f"Samples   : {len(samples)}\n")
        fh.write("\n")

        if not hits:
            fh.write("RESULT: No known drug resistance mutations detected.\n\n")
        else:
            fh.write(f"RESULT: {len(hits)} resistance mutation(s) detected!\n\n")
            fh.write("-" * 80 + "\n")

            # Group by drug class
            by_class: dict[str, list] = {}
            for h in hits:
                by_class.setdefault(h["drug_class"], []).append(h)

            for cls, class_hits in by_class.items():
                fh.write(f"\n[{cls} Resistance]\n")
                for h in class_hits:
                    fh.write(
                        f"  Gene     : {h['gene']}\n"
                        f"  Drug     : {h['drug']}\n"
                        f"  Mutation : {h['mutation']} ({h['aa_change']})\n"
                        f"  Level    : {h['resistance_level']}\n"
                        f"  Position : {h['chrom']}:{h['pos']} {h['ref']}>{h['alt']}\n"
                    )
                    for s in samples:
                        gt = h["genotypes"].get(s, {}).get("GT", ".")
                        if gt not in (".", "0", "0/0", "0|0"):
                            fh.write(f"  Sample   : {s}  GT={gt}\n")
                    fh.write("\n")

        # Interpretation guide
        fh.write("=" * 80 + "\n")
        fh.write("INTERPRETATION GUIDE\n")
        fh.write("=" * 80 + "\n")
        fh.write(
            "High     - Strong evidence of resistance; treatment likely to fail.\n"
            "Moderate - Possible resistance; use drug with caution.\n"
            "Low      - Limited evidence; clinical significance uncertain.\n\n"
            "CLINICAL RECOMMENDATIONS:\n"
            "  1. Consult WHO MDT guidelines for M. leprae treatment.\n"
            "  2. Consider alternative drug regimens for HIGH-level mutations.\n"
            "  3. Perform phenotypic susceptibility testing where possible.\n"
            "  4. Monitor treatment response closely.\n\n"
        )

        fh.write("=" * 80 + "\n")
        fh.write("MUTATION DATABASE REFERENCE\n")
        fh.write("=" * 80 + "\n")
        for gene, info in RESISTANCE_DB.items():
            fh.write(f"\n{gene}  ({info['drug']}):\n")
            for mut, lvl in info["mutations"].items():
                fh.write(f"  {mut:<10} {lvl}\n")

        fh.write(
            "\nReferences:\n"
            "  - WHO Guidelines for Leprosy Diagnosis, Treatment and Prevention (2018)\n"
            "  - Benjak et al. (2018) Phylogenomics and AMR of M. leprae\n"
            "  - Cambau & Drancourt (2014) Drug resistance in leprosy\n"
            "  - Matsuoka et al. (2007) Drug resistance in leprosy\n"
        )


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def parse_args():
    parser = argparse.ArgumentParser(
        description="Analyze M. leprae drug resistance mutations from an annotated VCF."
    )
    parser.add_argument("vcf", help="SnpEff-annotated VCF file (plain or bgzipped)")
    parser.add_argument(
        "-o", "--output",
        default="resistance_mutations.tsv",
        help="Output TSV table (default: resistance_mutations.tsv)",
    )
    parser.add_argument(
        "-r", "--report",
        default="resistance_report.txt",
        help="Output human-readable report (default: resistance_report.txt)",
    )
    return parser.parse_args()


def main():
    args = parse_args()

    print(f"[INFO] Parsing VCF: {args.vcf}")
    try:
        variants, samples = parse_vcf(args.vcf)
    except FileNotFoundError:
        print(f"[ERROR] VCF file not found: {args.vcf}", file=sys.stderr)
        sys.exit(1)

    print(f"[INFO] Loaded {len(variants)} variants across {len(samples)} sample(s)")

    all_hits = []
    for v in variants:
        all_hits.extend(check_resistance(v))

    print(f"[INFO] Detected {len(all_hits)} resistance mutation hit(s)")

    write_tsv(all_hits, samples, args.output)
    print(f"[INFO] TSV table written  : {args.output}")

    write_report(all_hits, samples, args.vcf, args.report)
    print(f"[INFO] Report written     : {args.report}")

    if all_hits:
        print("\n[WARNING] Drug resistance mutations detected! Review report carefully.")
        sys.exit(2)  # Non-zero exit so pipelines can detect resistance
    else:
        print("\n[OK] No known drug resistance mutations detected.")


if __name__ == "__main__":
    main()
