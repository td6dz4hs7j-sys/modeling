"""Enumerate Q4 partitions while preserving the validated Q3 schedule."""
from __future__ import annotations

import argparse
import csv
import hashlib
import itertools
import json
import math
import os
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(os.environ.get("Q4_Q3_SOURCE", str(ROOT / "results" / "q3_current")))
OUT = ROOT / "results" / "q4_current"
TYPES = ("A_uav", "B_uav", "C_uav", "A_battery", "B_battery", "C_battery", "R_uav", "R_component")
STOCK = dict(zip(TYPES, (4, 2, 2, 6, 4, 4, 2, 6)))


def read_csv(name):
    with (SOURCE / name).open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def sites_of(sortie):
    return tuple(sortie["service_order"].split("→"))


def connected_components(sorties):
    parent = {f"S{i:03d}": f"S{i:03d}" for i in range(1, 16)}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for s in sorties:
        sites = sites_of(s)
        assert sites and all(site in parent for site in sites)
        for site in sites[1:]:
            parent[find(site)] = find(sites[0])
    groups = defaultdict(list)
    for site in parent:
        groups[find(site)].append(site)
    return tuple(sorted((tuple(sorted(v)) for v in groups.values()), key=lambda x: x[0]))


def relay_route_map(relays, certificate):
    mapping = {r["id"]: set() for r in relays}
    for c in certificate:
        if c["provider"] == "G01":
            continue
        t0, t1 = float(c["t0"]), float(c["t1"])
        hits = [r for r in relays if r["uav"] == c["provider"]
                and float(r["serviceStart_s"]) <= t0 + 1e-6
                and float(r["serviceEnd_s"]) >= t1 - 1e-6]
        assert len(hits) == 1, (c, hits)
        mapping[hits[0]["id"]].add(int(c["route"]))
    assert all(mapping.values())
    return mapping


def load_inputs():
    sorties = read_csv("transport_sorties.csv")
    relays = read_csv("relay_sorties.csv")
    certificate = read_csv("continuous_communication_certificate.csv")
    deliveries = read_csv("box_deliveries.csv")
    assert len(sorties) == 23 and len(relays) >= 1 and len(certificate) > 0 and len(deliveries) == 80
    assert {s["sortie_id"] for s in sorties} == {d["sortie_id"] for d in deliveries}
    assert len({d["box_id"] for d in deliveries}) == 80
    assert all(int(c["route"]) in range(1, 24) and float(c["t1"]) > float(c["t0"]) for c in certificate)
    return sorties, relays, certificate, deliveries


def group_data(sites, sorties, relays, relay_routes, deliveries):
    sites = set(sites)
    selected = [(i + 1, s) for i, s in enumerate(sorties) if set(sites_of(s)) <= sites]
    assert all(not (set(sites_of(s)) & sites) or set(sites_of(s)) <= sites for s in sorties)
    route_ids = {i for i, _ in selected}
    needed_relays = [r for r in relays if relay_routes[r["id"]] & route_ids]
    resources = defaultdict(set)
    for _, s in selected:
        t = s["uav_type"]
        resources[f"{t}_uav"].add(s["uav_id"])
        resources[f"{t}_battery"].add(s["battery_id"])
    for r in needed_relays:
        resources["R_uav"].add(r["uav"])
        resources["R_component"].add(r["component"])
    # The Q3 mission times stay fixed. Identical assets can be relabeled within
    # one group; interval-graph coloring gives the exact minimum inventory.
    intervals = defaultdict(list)
    for _, s in selected:
        start, end = float(s["start_s"]), float(s["return_s"])
        t = s["uav_type"]
        intervals[f"{t}_uav"].append((start, end, s["sortie_id"]))
        intervals[f"{t}_battery"].append((start, end + charge_s(t, float(s["energy_kWh"])), s["sortie_id"]))
    for r in needed_relays:
        start, end = float(r["start_s"]), float(r["return_s"])
        intervals["R_uav"].append((start, float(r["ready_s"]), r["id"]))
        intervals["R_component"].append((start, float(r["componentReady_s"]), r["id"]))
    fixed_id_count = {key: len(resources[key]) for key in TYPES}
    count = fixed_id_count.copy()
    peak_count = {key: peak_overlap(intervals[key]) for key in TYPES}
    transport_work = sum(float(s["operation_s"]) for _, s in selected)
    relay_work = sum(float(r["return_s"]) - float(r["start_s"]) for r in needed_relays)
    makespan = max([float(s["return_s"]) for _, s in selected] + [float(r["return_s"]) for r in needed_relays])
    boxes = [d for d in deliveries if d["area"] in sites]
    return {"sites": tuple(sorted(sites)), "sorties": tuple(i for i, _ in selected),
            "relay_ids": tuple(r["id"] for r in needed_relays), "resources": count,
            "resource_ids": {k: tuple(sorted(resources[k])) for k in TYPES},
            "fixed_id_count": fixed_id_count,
            "peak_lower_bound": peak_count,
            "transport_work_s": transport_work, "relay_work_s": relay_work,
            "work_s": transport_work + relay_work, "makespan_s": makespan,
            "boxes": len(boxes), "transport_energy_kWh": sum(float(s["energy_kWh"]) for _, s in selected),
            "relay_energy_kWh": sum(float(r["energy_kWh"]) for r in needed_relays)}


def charge_s(t, energy):
    capacity = {"A": 4.5, "B": 4.0, "C": 8.0}[t]
    full = {"A": 1800, "B": 2400, "C": 3000}[t]
    soc = 1 - energy / capacity
    assert soc >= 0.2 - 1e-8
    return full * (0.65 * (0.9 - soc) / 0.9 + 0.35) if soc < 0.9 else full * 0.35 * (1 - soc) / 0.1


def peak_overlap(intervals):
    events = []
    for start, end, _ in intervals:
        assert end > start
        events.extend(((round(start, 5), 1), (round(end, 5), -1)))
    active = best = 0
    for _, delta in sorted(events):  # End before start at a shared endpoint.
        active += delta
        best = max(best, active)
        assert active >= 0
    assert active == 0
    return best


def evaluate(labels, components, sorties, relays, relay_routes, deliveries):
    k = max(labels) + 1
    groups = [group_data(itertools.chain.from_iterable(components[j] for j, v in enumerate(labels) if v == i),
                         sorties, relays, relay_routes, deliveries) for i in range(k)]
    total = {key: sum(g["resources"][key] for g in groups) for key in TYPES}
    peak_lower_bound = {key: sum(g["peak_lower_bound"][key] for g in groups) for key in TYPES}
    redundancy = {key: total[key] - peak_lower_bound[key] for key in TYPES}
    assert all(value >= 0 for value in redundancy.values())
    gap = {key: max(0, total[key] - STOCK[key]) for key in TYPES}
    spare = {key: max(0, STOCK[key] - total[key]) for key in TYPES}
    works = [g["work_s"] for g in groups]
    mean = sum(works) / k
    cv = math.sqrt(sum((x - mean) ** 2 for x in works) / k) / mean
    return {"k": k, "groups": groups, "total": total, "peak_lower_bound": peak_lower_bound,
            "redundancy": redundancy, "redundancy_units": sum(redundancy.values()),
            "gap": gap, "spare": spare,
            "gap_units": sum(gap.values()), "total_units": sum(total.values()),
            "work_cv": cv, "work_ratio": max(works) / min(works),
            "relay_task_copies": sum(len(g["relay_ids"]) for g in groups),
            "max_group_makespan_s": max(g["makespan_s"] for g in groups)}


def partitions(n, k):
    labels = [0] * n

    def rec(i, used):
        if i == n:
            if used == k:
                yield tuple(labels)
            return
        for label in range(min(used + 1, k)):
            labels[i] = label
            yield from rec(i + 1, max(used, label + 1))

    yield from rec(1, 1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--smoke", action="store_true")
    args = parser.parse_args()
    sorties, relays, cert, deliveries = load_inputs()
    components = connected_components(sorties)
    relay_routes = relay_route_map(relays, cert)
    if args.smoke:
        labels = (0,) + (1,) * (len(components) - 1)
        result = evaluate(labels, components, sorties, relays, relay_routes, deliveries)
        assert sum(g["boxes"] for g in result["groups"]) == 80
        print(json.dumps({"components": components, "gap": result["gap"],
                          "total": result["total"], "relay_task_copies": result["relay_task_copies"]}, ensure_ascii=False))
        return
    OUT.mkdir(parents=True, exist_ok=True)
    all_results = {}
    for k in (2, 3):
        candidates = []
        for labels in partitions(len(components), k):
            x = evaluate(labels, components, sorties, relays, relay_routes, deliveries)
            x["labels"] = labels
            candidates.append(x)
        metrics = ("gap_units", "total_units", "work_cv", "redundancy_units")
        for x in candidates:
            x["spare_units"] = sum(x["spare"].values())
        bounds = {m: (min(x[m] for x in candidates), max(x[m] for x in candidates)) for m in metrics}
        weights = dict(zip(metrics, (0.35, 0.25, 0.30, 0.10)))
        for x in candidates:
            x["score"] = sum(weights[m] * (x[m] - bounds[m][0]) /
                             max(bounds[m][1] - bounds[m][0], 1e-12) for m in metrics)
        candidates.sort(key=lambda x: (x["score"], x["gap_units"], x["total_units"], x["work_cv"]))
        # A three-group unit should do meaningful work; CV<=0.25 is an
        # explicit recommendation preference, not an added feasibility rule.
        chosen = next(x for x in candidates if x["work_cv"] <= 0.25) if k == 3 else candidates[0]
        gap_first = min(candidates, key=lambda x: (x["gap_units"], x["total_units"], x["work_cv"]))
        all_results[k] = {"searched": len(candidates), "bounds": bounds, "weights": weights,
                          "balanced_preference_cv_max": 0.25 if k == 3 else None,
                          "recommended": chosen, "unrestricted_score_best": candidates[0],
                          "gap_first": gap_first}
        with (OUT / f"q4_{k}group_search.csv").open("w", encoding="utf-8-sig", newline="") as f:
            w = csv.writer(f)
            w.writerow(["rank", "score", "gap_units", "total_units", "spare_units", "work_cv",
                        "redundancy_units", "work_ratio", "relay_task_copies", "max_group_makespan_s", "groups"])
            for i, x in enumerate(candidates, 1):
                w.writerow([i, x["score"], x["gap_units"], x["total_units"], x["spare_units"],
                            x["redundancy_units"],
                            x["work_cv"], x["work_ratio"], x["relay_task_copies"],
                            x["max_group_makespan_s"], " | ".join(";".join(g["sites"]) for g in x["groups"])])
    for k, data in all_results.items():
        validate_partition(data["recommended"], sorties, relays, cert, deliveries, relay_routes)
    serial = {"q3_source_sha256": {name: hashlib.sha256((SOURCE / name).read_bytes()).hexdigest()
                                      for name in ("Q3_结果提交.xlsx", "transport_sorties.csv", "relay_sorties.csv",
                                                   "continuous_communication_certificate.csv", "box_deliveries.csv")},
              "connected_components": components, "inventory": STOCK, "results": all_results}
    (OUT / "q4_results.json").write_text(json.dumps(serial, ensure_ascii=False, indent=2), encoding="utf-8")
    write_summary(all_results)
    print(json.dumps({str(k): {"searched": d["searched"], "score": d["recommended"]["score"],
                                "groups": [g["sites"] for g in d["recommended"]["groups"]],
                                "total": d["recommended"]["total"], "gap": d["recommended"]["gap"],
                                "work_cv": d["recommended"]["work_cv"]}
                      for k, d in all_results.items()}, ensure_ascii=False))


def validate_partition(x, sorties, relays, cert, deliveries, relay_routes):
    assert len(x["groups"]) == x["k"]
    assert set().union(*(set(g["sites"]) for g in x["groups"])) == {f"S{i:03d}" for i in range(1, 16)}
    assert sum(len(g["sites"]) for g in x["groups"]) == 15
    assert sum(len(g["sorties"]) for g in x["groups"]) == len(sorties)
    assert sum(g["boxes"] for g in x["groups"]) == len(deliveries)
    assert abs(sum(g["transport_energy_kWh"] for g in x["groups"]) -
               sum(float(s["energy_kWh"]) for s in sorties)) < 1e-8
    for g in x["groups"]:
        route_ids = set(g["sorties"])
        for i in route_ids:
            assert set(sites_of(sorties[i - 1])) <= set(g["sites"])
        expected_relays = {rid for rid, routes in relay_routes.items() if routes & route_ids}
        assert set(g["relay_ids"]) == expected_relays
        assert all(g["resources"][t] <= g["fixed_id_count"][t] for t in TYPES)
    for c in cert:
        groups = [g for g in x["groups"] if int(c["route"]) in g["sorties"]]
        assert len(groups) == 1
        if c["provider"] != "G01":
            assert any(r["id"] in groups[0]["relay_ids"] for r in relays
                       if r["uav"] == c["provider"] and
                       float(r["serviceStart_s"]) <= float(c["t0"]) + 1e-6 and
                       float(r["serviceEnd_s"]) >= float(c["t1"]) - 1e-6)
    assert x["gap"] == {t: max(0, x["total"][t] - STOCK[t]) for t in TYPES}
    assert x["spare"] == {t: max(0, STOCK[t] - x["total"][t]) for t in TYPES}


def write_summary(results):
    with (OUT / "q4_group_resources.csv").open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["K", "group", "sites", "boxes", "transport_sorties", "relay_sortie_copies",
                    *TYPES, "transport_work_s", "relay_work_s", "work_s", "makespan_s",
                    "transport_energy_kWh", "relay_energy_kWh"])
        for k, data in results.items():
            for i, g in enumerate(data["recommended"]["groups"], 1):
                w.writerow([k, i, ";".join(g["sites"]), g["boxes"], len(g["sorties"]), len(g["relay_ids"]),
                            *(g["resources"][t] for t in TYPES), g["transport_work_s"], g["relay_work_s"],
                            g["work_s"], g["makespan_s"], g["transport_energy_kWh"], g["relay_energy_kWh"]])
    with (OUT / "q4_comparison.csv").open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["K", "searched", "score", "gap_units", "total_units", "spare_units", "redundancy_units", "work_cv",
                    "work_ratio", "relay_task_copies", "max_group_makespan_s", *[f"need_{t}" for t in TYPES],
                    *[f"gap_{t}" for t in TYPES], *[f"spare_{t}" for t in TYPES]])
        for k, data in results.items():
            x = data["recommended"]
            w.writerow([k, data["searched"], x["score"], x["gap_units"], x["total_units"],
                        x["spare_units"], x["redundancy_units"], x["work_cv"], x["work_ratio"], x["relay_task_copies"],
                        x["max_group_makespan_s"], *(x["total"][t] for t in TYPES),
                        *(x["gap"][t] for t in TYPES), *(x["spare"][t] for t in TYPES)])


if __name__ == "__main__":
    main()
