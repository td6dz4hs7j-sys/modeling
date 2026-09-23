"""问题一结果的机器可读约束验证。"""

from __future__ import annotations

from collections import Counter
from typing import Iterable

from .batching import BatchEvaluator
from .energy_model import equivalent_range_m, round_trip_energy_kwh
from .models import Batch, CargoBox, Solution, UAVType


def validate_solution(
    boxes: Iterable[CargoBox],
    solution: Solution,
    evaluator: BatchEvaluator,
) -> dict:
    boxes = tuple(boxes)
    box_by_id = {box.box_id: box for box in boxes}
    errors: list[str] = []
    checks: dict[str, bool] = {}

    counts = Counter(box_id for batch in solution.batches for box_id in batch.box_ids)
    checks["all_boxes_present_once"] = (
        set(counts) == set(box_by_id)
        and all(count == 1 for count in counts.values())
    )
    if not checks["all_boxes_present_once"]:
        errors.append(f"箱体覆盖/唯一性失败: {counts}")

    checks["no_cross_area_batch"] = True
    checks["mass_capacity"] = True
    checks["volume_capacity"] = True
    checks["energy_reserve"] = True
    checks["range_constraint"] = True
    checks["finite_units"] = True
    for batch in solution.batches:
        if batch.uav_type_id not in evaluator.uav_types:
            checks["finite_units"] = False
            errors.append(f"未知机型: {batch.uav_type_id}")
            continue
        uav = evaluator.uav_types[batch.uav_type_id]
        route = evaluator.routes.get(batch.service_area_id)
        if route is None:
            checks["finite_units"] = False
            errors.append(f"未知服务区: {batch.service_area_id}")
            continue
        box_areas = {
            box_by_id[box_id].service_area_id
            for box_id in batch.box_ids
            if box_id in box_by_id
        }
        if box_areas != {batch.service_area_id}:
            checks["no_cross_area_batch"] = False
            errors.append(f"架次 {batch.batch_id} 跨服务区或含未知箱体")
        mass = sum(box_by_id[box_id].mass_kg for box_id in batch.box_ids if box_id in box_by_id)
        volume = sum(box_by_id[box_id].volume_m3 for box_id in batch.box_ids if box_id in box_by_id)
        safe = evaluator.safe_payloads[(batch.uav_type_id, batch.service_area_id)]
        if mass > safe + 1e-7:
            checks["mass_capacity"] = False
            errors.append(f"架次 {batch.batch_id} 超过最大安全载荷")
        if volume > uav.volume_capacity_m3 + 1e-7:
            checks["volume_capacity"] = False
            errors.append(f"架次 {batch.batch_id} 超过装载体积")
        energy = round_trip_energy_kwh(
            evaluator.provider,
            uav,
            route,
            mass,
        )
        allowed = (1.0 - uav.reserve_ratio) * uav.usable_energy_kwh
        if energy > allowed + 1e-7:
            checks["energy_reserve"] = False
            errors.append(f"架次 {batch.batch_id} 超过返航安全余量")
        if route.outbound.distance_m + route.inbound.distance_m > equivalent_range_m(uav, mass) + 1e-7:
            checks["range_constraint"] = False
            errors.append(f"架次 {batch.batch_id} 超过等效航程")
        if not all(
            value >= -1e-9
            for value in (mass, volume, batch.flight_time_s, batch.energy_kwh)
        ):
            checks["finite_units"] = False
            errors.append(f"架次 {batch.batch_id} 存在负值")

    checks["solution_totals_match"] = (
        solution.total_sorties == len(solution.batches)
        and abs(solution.total_energy_kwh - sum(batch.energy_kwh for batch in solution.batches)) <= 1e-7
        and abs(solution.total_time_s - sum(batch.flight_time_s for batch in solution.batches)) <= 1e-7
    )
    if not checks["solution_totals_match"]:
        errors.append("Solution 汇总指标与架次明细不一致")
    checks["all_constraints"] = all(checks.values())
    return {
        "passed": not errors,
        "checks": checks,
        "errors": errors,
        "n_boxes": len(boxes),
        "n_batches": len(solution.batches),
        "method": solution.method,
        "complete_search": solution.complete_search,
        "notes": list(solution.notes),
    }
