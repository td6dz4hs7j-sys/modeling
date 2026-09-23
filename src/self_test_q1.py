"""结构等价小实例的自检。

这里的能耗函数仅用于验证软件接口和约束链，不代表题目物理参数，
也不会写入正式结果目录。真实运行必须通过 --energy-provider 注入经
题目附件核验的公式。
"""

from __future__ import annotations

from dataclasses import dataclass

from .batching import BatchEvaluator, ffd_baseline, local_search_improve
from .energy_model import EnergyProvider, leg_energy_kwh
from .models import CargoBox, LegGeometry, RouteGeometry, UAVType
from .payload_solver import max_safe_payload
from .validation import validate_solution


@dataclass(frozen=True)
class DemoProvider:
    source: str = "self-test-only; not competition data"

    def horizontal_kwh(self, uav: UAVType, leg: LegGeometry, payload_kg: float) -> float:
        return leg.distance_m * (0.00018 + 0.000015 * payload_kg)

    def climb_kwh(self, uav: UAVType, leg: LegGeometry, payload_kg: float) -> float:
        return leg.climb_m * (0.0012 + 0.00002 * payload_kg)


def run() -> None:
    provider: EnergyProvider = DemoProvider()
    route = RouteGeometry(
        "S001",
        LegGeometry("O01", "S001", 1000.0, 100.0, 40.0, 140.0, 0.0, 100.0, 90.0),
        LegGeometry("S001", "O01", 1000.0, 40.0, 100.0, 140.0, 100.0, 0.0, 90.0),
    )
    routes = {"S001": route}
    uavs = {
        "A": UAVType("A", 2.0, 2500.0, 1600.0, 8.0, 15.0, 8.0, 5.0, 0.2, 1.0),
        "B": UAVType("B", 4.0, 3000.0, 1900.0, 8.0, 15.0, 8.0, 8.0, 0.2, 2.0),
        "C": UAVType("C", 6.0, 3500.0, 2200.0, 8.0, 15.0, 8.0, 12.0, 0.2, 3.0),
    }
    boxes = (
        CargoBox("D001", "S001", 1.5, 0.7),
        CargoBox("D002", "S001", 1.2, 0.6),
        CargoBox("D003", "S001", 0.9, 0.5),
        CargoBox("D004", "S001", 0.8, 0.4),
        CargoBox("D005", "S001", 0.7, 0.3),
        CargoBox("D006", "S001", 0.6, 0.2),
    )
    payloads = [
        max_safe_payload(provider, uavs[type_id], route)
        for type_id in sorted(uavs)
    ]
    assert all(item.feasible_at_zero_payload for item in payloads)
    safe = {
        (item.uav_type_id, item.service_area_id): item.safe_payload_kg
        for item in payloads
    }
    evaluator = BatchEvaluator(provider, routes, uavs, safe)
    baseline = ffd_baseline(boxes, evaluator)
    assert validate_solution(boxes, baseline, evaluator)["passed"]
    improved = local_search_improve(boxes, evaluator, baseline, max_iterations=20)
    assert validate_solution(boxes, improved, evaluator)["passed"]
    assert improved.total_sorties <= baseline.total_sorties
    print("Q1 software self-test: PASS")
    print("This is a structure-equivalent check only; no competition result was produced.")


if __name__ == "__main__":
    run()
