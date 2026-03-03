import csv
import glob
import json
import os

INPUT_FOLDER = "tools/ddinter_raw"
OUTPUT_FILE = "assets/interactions.json"

def norm(s):
    return (s or "").strip()

def norm_key(s):
    return norm(s).lower()

def pick_col(headers, candidates):
    hset = {h.lower(): h for h in headers}
    for c in candidates:
        if c.lower() in hset:
            return hset[c.lower()]
    return None

def first_nonempty(row, cols):
    for c in cols:
        v = norm(row.get(c, ""))
        if v:
            return v
    return ""

def normalize_sev(s):
    s = norm(s).lower()
    if not s:
        return "unknown"
    if s in ("major", "severe", "high", "contraindicated"):
        return "major"
    if s in ("moderate", "medium"):
        return "moderate"
    if s in ("minor", "low"):
        return "minor"
    return s

rules = []
seen = set()

csv_files = glob.glob(os.path.join(INPUT_FOLDER, "*.csv"))
if not csv_files:
    raise SystemExit(f"No csv files found in {INPUT_FOLDER}")

for file in csv_files:
    print("Processing:", file)
    with open(file, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        headers = reader.fieldnames or []
        if not headers:
            continue

        col_a = pick_col(headers, ["drug1", "drug_1", "drug_a", "drug_a_name", "drugname1", "drugname_1", "name_a", "Drug1", "DrugA"])
        col_b = pick_col(headers, ["drug2", "drug_2", "drug_b", "drug_b_name", "drugname2", "drugname_2", "name_b", "Drug2", "DrugB"])

        if col_a is None or col_b is None:
            print("  Could not detect drug columns. Headers are:")
            print("  ", headers)
            continue

        col_sev = pick_col(headers, ["severity", "risk", "risk_level", "level", "grade", "interaction_level"])
        col_cause = pick_col(headers, ["mechanism", "cause", "description", "interaction", "interaction_description"])
        col_effect = pick_col(headers, ["effect", "clinical_effect", "outcome", "result"])
        col_advice = pick_col(headers, ["management", "advice", "recommendation", "suggestion", "handling"])

        for row in reader:
            a = norm_key(row.get(col_a))
            b = norm_key(row.get(col_b))
            if not a or not b:
                continue

            key = tuple(sorted([a, b]))
            if key in seen:
                continue
            seen.add(key)

            severity = normalize_sev(row.get(col_sev, "")) if col_sev else "unknown"

            cause = norm(row.get(col_cause, "")) if col_cause else ""
            effect = norm(row.get(col_effect, "")) if col_effect else ""
            advice = norm(row.get(col_advice, "")) if col_advice else ""

            if not cause:
                cause = "—"
            if not effect:
                effect = "—"
            if not advice:
                advice = "—"

            rules.append({
                "a": a,
                "b": b,
                "severity": severity,
                "cause": cause,
                "effect": effect,
                "advice": advice
            })

print("Total unique interactions:", len(rules))

with open(OUTPUT_FILE, "w", encoding="utf-8") as w:
    json.dump({"version": 3, "rules": rules}, w, ensure_ascii=False)

print("Saved to", OUTPUT_FILE)