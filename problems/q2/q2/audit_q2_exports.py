"""Independent file-level audit of the frozen Q2 result and submission workbook."""
import csv
import json
import math
import os
from pathlib import Path
import openpyxl

ROOT = Path(__file__).resolve().parents[1]
OUT = Path(os.environ.get("Q2_AUDIT_OUT", ROOT / "results" / "q2_all_ontime"))


def rows(name):
    with (OUT / name).open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def close(a, b, tol=1e-6):
    return abs(float(a) - float(b)) <= tol


def audit():
    issues = []
    sorties = rows("q2_final_sorties.csv")
    boxes = rows("q2_final_box_delivery.csv")
    batteries = rows("q2_final_battery_SOC_charge_ready.csv")
    uav = rows("q2_final_uav_resource_summary.csv")
    metrics = json.loads((OUT / "q2_final_metrics.json").read_text(encoding="utf-8"))
    val = json.loads((OUT / "q2_final_validation.json").read_text(encoding="utf-8"))
    tests = rows("q2_strict_mutation_tests.csv")

    expected_sorties = int(metrics["final"]["N"])
    if len(sorties) != expected_sorties or len({r["sortie_id"] for r in sorties}) != expected_sorties:
        issues.append("sortie count or uniqueness")
    if len(boxes) != 80 or len({r["box_id"] for r in boxes}) != 80:
        issues.append("box count or uniqueness")
    if sum(int(float(r["rejected"])) for r in tests) != 13 or len(tests) != 13:
        issues.append("mutation test failures")
    if val["status"] != "PASS" or not val["requireAllExpectedOnTime"]:
        issues.append("strict validator status")
    if len(uav) != 8:
        issues.append("physical UAV inventory count")
    if len({r["battery_id"] for r in batteries}) != 14:
        issues.append("physical battery inventory count")
    if not all(float(r["arrival_s"]) <= float(r["expected_s"]) + 1e-6 for r in boxes):
        issues.append("expected delivery violation")
    if not all(r["hard_deadline_met"] == "1" for r in boxes):
        issues.append("hard deadline violation")
    ids = {r["sortie_id"] for r in sorties}
    if any(r["sortie_id"] not in ids for r in boxes):
        issues.append("box references missing sortie")
    for s in sorties:
        b = [x for x in boxes if x["sortie_id"] == s["sortie_id"]]
        if {x["box_id"] for x in b} != set(s["box_ids"].split(";")):
            issues.append("sortie/box membership mismatch")
        if not close(float(s["return_s"]) - float(s["start_s"]), s["operation_s"]):
            issues.append("operation/return mismatch")
    if not close(sum(float(s["energy_kWh"]) for s in sorties), metrics["final"]["energy_kWh"]):
        issues.append("total energy mismatch")
    if not close(max(float(s["return_s"]) for s in sorties), metrics["final"]["Cmax_s"]):
        issues.append("makespan mismatch")
    if not close(sum(float(s["operation_s"]) for s in sorties) / 3600,
                 metrics["final_cumulative_operation_h"]):
        issues.append("cumulative operation mismatch")

    for key in ("uav_id", "battery_id"):
        for ident in {s[key] for s in sorties}:
            rr = sorted((s for s in sorties if s[key] == ident), key=lambda s: float(s["start_s"]))
            for prev, curr in zip(rr, rr[1:]):
                end = float(prev["return_s"])
                if key == "battery_id":
                    record = next((b for b in batteries if b["battery_id"] == ident
                                   and b["sortie_id"] == prev["sortie_id"]), None)
                    if record is None:
                        issues.append("battery schedule row missing")
                        continue
                    end = float(record["ready_s"])
                if float(curr["start_s"]) < end - 1e-6:
                    issues.append(f"{key} interval overlap")
    book = openpyxl.load_workbook(OUT / "Q2_结果提交.xlsx", read_only=True, data_only=True)
    sheet_s, sheet_b = book.worksheets[1], book.worksheets[2]
    ws = list(sheet_s.values)[1:]
    wb = list(sheet_b.values)[1:]
    ws = [x for x in ws if x[0] is not None]
    wb = [x for x in wb if x[0] is not None]
    if len(ws) != len(sorties) or len(wb) != len(boxes):
        issues.append("submission workbook row counts")
    else:
        for r, x in zip(sorties, ws):
            for a, b in zip(("sortie_id", "uav_id", "uav_type", "battery_id", "start_s",
                             "service_order", "return_s", "energy_kWh"), x):
                if a in ("start_s", "return_s", "energy_kWh"):
                    good = close(r[a], b)
                else:
                    good = str(r[a]) == str(b)
                if not good:
                    issues.append("submission sortie cell mismatch")
                    break
        for r, x in zip(boxes, wb):
            for a, b in zip(("box_id", "sortie_id", "area", "arrival_s"), x):
                good = close(r[a], b) if a == "arrival_s" else str(r[a]) == str(b)
                if not good:
                    issues.append("submission box cell mismatch")
                    break
    result = {"status": "PASS" if not issues else "FAIL", "issues": sorted(set(issues)),
              "sorties": len(sorties), "boxes": len(boxes), "on_time": sum(
                  float(r["arrival_s"]) <= float(r["expected_s"]) + 1e-6 for r in boxes),
              "uav_count": len(uav), "battery_count": len({r["battery_id"] for r in batteries}),
              "mutation_tests_rejected": sum(int(float(r["rejected"])) for r in tests)}
    (OUT / "q2_export_audit.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=True))
    if issues:
        raise SystemExit(1)


if __name__ == "__main__":
    audit()
