"""返航安全余量比例敏感性扫描。"""

from __future__ import annotations

from typing import Iterable

from .energy_model import EnergyProvider
from .models import CargoBox, RouteGeometry, UAVType
from .optimization import solve_q1
from .payload_solver import override_reserve


def scan_reserve_ratio(
    boxes: Iterable[CargoBox],
    uav_types: dict[str, UAVType],
    routes: dict[str, RouteGeometry],
    provider: EnergyProvider,
    reserve_values: Iterable[float],
    *,
    try_milp: bool = False,
    local_search_iterations: int = 200,
) -> tuple[dict, ...]:
    """每个 rho 重新跑安全载荷和组批，保留可复核指标。"""

    records: list[dict] = []
    for rho in reserve_values:
        if not 0 <= rho < 1:
            raise ValueError(f"rho 必须位于 [0,1): {rho}")
        varied = override_reserve(uav_types, rho)
        run = solve_q1(
            boxes,
            varied,
            routes,
            provider,
            try_milp=try_milp,
            local_search_iterations=local_search_iterations,
        )
        records.append(
            {
                "rho": rho,
                "safe_payloads_kg": {
                    f"{item.uav_type_id}/{item.service_area_id}": item.safe_payload_kg
                    for item in run.payload_results
                },
                "ffd": {
                    "sorties": run.baseline.total_sorties,
                    "energy_kwh": run.baseline.total_energy_kwh,
                    "time_s": run.baseline.total_time_s,
                },
                "local_search": {
                    "sorties": run.local_search.total_sorties,
                    "energy_kwh": run.local_search.total_energy_kwh,
                    "time_s": run.local_search.total_time_s,
                },
                "notes": list(run.notes),
            }
        )
    return tuple(records)


def detect_switch_points(records: Iterable[dict]) -> list[dict]:
    """只根据实际扫描记录报告离散结构切换，不插值虚构连续点。"""

    records = list(records)
    switches: list[dict] = []
    for previous, current in zip(records, records[1:]):
        changed = []
        for key in ("ffd", "local_search"):
            if previous[key]["sorties"] != current[key]["sorties"]:
                changed.append(f"{key}.sorties")
        if previous["safe_payloads_kg"] != current["safe_payloads_kg"]:
            changed.append("safe_payloads_kg")
        if changed:
            switches.append(
                {
                    "from_rho": previous["rho"],
                    "to_rho": current["rho"],
                    "changed_metrics": changed,
                }
            )
    return switches
