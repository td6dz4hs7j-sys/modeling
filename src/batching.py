"""问题一组批：先行基线、再做局部改进。

不使用遗传算法。基线必须先独立通过约束验证；局部搜索只接受让
(架次、总能耗、总时间) 字典序变好的可行邻域解。
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Iterable

from .energy_model import EnergyProvider, round_trip_energy_kwh, round_trip_time_s
from .exceptions import InfeasibleProblemError, InputContractError
from .models import Batch, CargoBox, RouteGeometry, Solution, UAVType


@dataclass
class _OpenBatch:
    service_area_id: str
    uav_type_id: str
    box_ids: list[str]
    mass_kg: float = 0.0
    volume_m3: float = 0.0


class BatchEvaluator:
    def __init__(
        self,
        provider: EnergyProvider,
        routes: dict[str, RouteGeometry],
        uav_types: dict[str, UAVType],
        safe_payloads: dict[tuple[str, str], float],
    ) -> None:
        self.provider = provider
        self.routes = routes
        self.uav_types = uav_types
        self.safe_payloads = safe_payloads

    def can_add(
        self,
        batch: _OpenBatch,
        box: CargoBox,
        *,
        tolerance: float = 1e-8,
    ) -> bool:
        if box.service_area_id != batch.service_area_id:
            return False
        uav = self.uav_types[batch.uav_type_id]
        safe = self.safe_payloads[(batch.uav_type_id, batch.service_area_id)]
        mass = batch.mass_kg + box.mass_kg
        volume = batch.volume_m3 + box.volume_m3
        if mass > safe + tolerance or volume > uav.volume_capacity_m3 + tolerance:
            return False
        energy = round_trip_energy_kwh(
            self.provider,
            uav,
            self.routes[batch.service_area_id],
            mass,
        )
        allowed = (1.0 - uav.reserve_ratio) * uav.usable_energy_kwh
        return energy <= allowed + tolerance

    def can_start(self, box: CargoBox, uav_type_id: str) -> bool:
        batch = _OpenBatch(
            service_area_id=box.service_area_id,
            uav_type_id=uav_type_id,
            box_ids=[],
        )
        return self.can_add(batch, box)

    def finalize(self, batch: _OpenBatch, ordinal: int) -> Batch:
        if not batch.box_ids:
            raise InputContractError("不能把空架次写入结果")
        uav = self.uav_types[batch.uav_type_id]
        route = self.routes[batch.service_area_id]
        energy = round_trip_energy_kwh(
            self.provider, uav, route, batch.mass_kg
        )
        allowed = (1.0 - uav.reserve_ratio) * uav.usable_energy_kwh
        if energy > allowed + 1e-8:
            raise InputContractError(
                f"架次 {batch.service_area_id}/{batch.uav_type_id} 能量约束失败"
            )
        time_s = round_trip_time_s(uav, route)
        return Batch(
            batch_id=f"Q1-{ordinal:03d}",
            service_area_id=batch.service_area_id,
            uav_type_id=batch.uav_type_id,
            box_ids=tuple(batch.box_ids),
            mass_kg=batch.mass_kg,
            volume_m3=batch.volume_m3,
            flight_time_s=time_s,
            energy_kwh=energy,
            return_soc_ratio=1.0 - energy / uav.usable_energy_kwh,
        )

    def evaluate_open(self, open_batches: Iterable[_OpenBatch]) -> tuple[Batch, ...]:
        return tuple(
            self.finalize(batch, ordinal)
            for ordinal, batch in enumerate(open_batches, start=1)
        )


def _box_order(
    boxes: Iterable[CargoBox],
    area_id: str,
    safe_payloads: dict[tuple[str, str], float],
    uav_types: dict[str, UAVType],
) -> list[CargoBox]:
    selected = [box for box in boxes if box.service_area_id == area_id]
    if not selected:
        return []
    max_safe = max(
        safe_payloads[(type_id, area_id)]
        for type_id in uav_types
    )
    max_volume = max(uav.volume_capacity_m3 for uav in uav_types.values())
    if max_safe <= 0 or max_volume <= 0:
        raise InfeasibleProblemError(f"服务区 {area_id} 没有正的可用装载能力")
    return sorted(
        selected,
        key=lambda box: (
            max(box.mass_kg / max_safe, box.volume_m3 / max_volume),
            box.mass_kg,
            box.volume_m3,
            box.box_id,
        ),
        reverse=True,
    )


def _choose_new_type(
    box: CargoBox,
    area_id: str,
    evaluator: BatchEvaluator,
) -> str:
    feasible = [
        type_id
        for type_id in evaluator.uav_types
        if evaluator.can_start(box, type_id)
    ]
    if not feasible:
        raise InfeasibleProblemError(
            f"货箱 {box.box_id} 在服务区 {area_id} 不能由任何机型单独承运"
        )
    return min(
        feasible,
        key=lambda type_id: (
            evaluator.safe_payloads[(type_id, area_id)],
            evaluator.uav_types[type_id].volume_capacity_m3,
            type_id,
        ),
    )


def ffd_baseline(
    boxes: Iterable[CargoBox],
    evaluator: BatchEvaluator,
    *,
    area_ids: Iterable[str] | None = None,
) -> Solution:
    """服务区内按装载压力递减、首个可行架次放置的确定性基线。"""

    boxes = tuple(boxes)
    areas = sorted(area_ids or {box.service_area_id for box in boxes})
    open_batches: list[_OpenBatch] = []
    for area_id in areas:
        for box in _box_order(
            boxes, area_id, evaluator.safe_payloads, evaluator.uav_types
        ):
            candidates = [
                (idx, batch)
                for idx, batch in enumerate(open_batches)
                if batch.service_area_id == area_id
                and evaluator.can_add(batch, box)
            ]
            if candidates:
                # 首先拟合最紧的可行架次；同值按原出现顺序。
                idx, _ = min(
                    candidates,
                    key=lambda item: (
                        evaluator.safe_payloads[
                            (item[1].uav_type_id, area_id)
                        ] - item[1].mass_kg - box.mass_kg,
                        evaluator.uav_types[
                            item[1].uav_type_id
                        ].volume_capacity_m3 - item[1].volume_m3 - box.volume_m3,
                        item[0],
                    ),
                )
                target = open_batches[idx]
            else:
                type_id = _choose_new_type(box, area_id, evaluator)
                target = _OpenBatch(area_id, type_id, [])
                open_batches.append(target)
            target.box_ids.append(box.box_id)
            target.mass_kg += box.mass_kg
            target.volume_m3 += box.volume_m3
    batches = evaluator.evaluate_open(open_batches)
    return _solution_from_batches(batches, "FFD baseline", complete_search=False)


def _solution_from_batches(
    batches: tuple[Batch, ...],
    method: str,
    *,
    complete_search: bool,
    notes: tuple[str, ...] = (),
) -> Solution:
    return Solution(
        batches=batches,
        total_sorties=len(batches),
        total_energy_kwh=sum(batch.energy_kwh for batch in batches),
        total_time_s=sum(batch.flight_time_s for batch in batches),
        method=method,
        complete_search=complete_search,
        notes=notes,
    )


def _objective(solution: Solution) -> tuple[float, float, float, tuple[str, ...]]:
    return (
        solution.total_sorties,
        solution.total_energy_kwh,
        solution.total_time_s,
        tuple(
            f"{batch.service_area_id}:{batch.uav_type_id}:{','.join(batch.box_ids)}"
            for batch in solution.batches
        ),
    )


def _to_open_batches(
    solution: Solution,
    boxes_by_id: dict[str, CargoBox],
) -> list[_OpenBatch]:
    result: list[_OpenBatch] = []
    for batch in solution.batches:
        result.append(
            _OpenBatch(
                service_area_id=batch.service_area_id,
                uav_type_id=batch.uav_type_id,
                box_ids=list(batch.box_ids),
                mass_kg=sum(boxes_by_id[box_id].mass_kg for box_id in batch.box_ids),
                volume_m3=sum(boxes_by_id[box_id].volume_m3 for box_id in batch.box_ids),
            )
        )
    return result


def local_search_improve(
    boxes: Iterable[CargoBox],
    evaluator: BatchEvaluator,
    baseline: Solution,
    *,
    max_iterations: int = 200,
    method_name: str = "local search from FFD",
) -> Solution:
    """在基线邻域中做 relocate/swap，始终保持硬约束。"""

    boxes_by_id = {box.box_id: box for box in boxes}
    current = baseline
    for _ in range(max_iterations):
        best = current
        open_batches = _to_open_batches(current, boxes_by_id)
        # Relocate：把一个箱体移到同服务区的另一个已有架次。
        for source_idx, source in enumerate(open_batches):
            if len(source.box_ids) <= 1:
                continue
            for box_id in tuple(source.box_ids):
                box = boxes_by_id[box_id]
                for target_idx, target in enumerate(open_batches):
                    if source_idx == target_idx or target.service_area_id != source.service_area_id:
                        continue
                    if not evaluator.can_add(target, box):
                        continue
                    candidate_open = _copy_open(open_batches)
                    candidate_open[source_idx].box_ids.remove(box_id)
                    candidate_open[source_idx].mass_kg -= box.mass_kg
                    candidate_open[source_idx].volume_m3 -= box.volume_m3
                    candidate_open[target_idx].box_ids.append(box_id)
                    candidate_open[target_idx].mass_kg += box.mass_kg
                    candidate_open[target_idx].volume_m3 += box.volume_m3
                    candidate_open = [item for item in candidate_open if item.box_ids]
                    candidate = _solution_from_batches(
                        evaluator.evaluate_open(candidate_open),
                        method_name,
                        complete_search=False,
                    )
                    if _objective(candidate) < _objective(best):
                        best = candidate
        # Swap：交换同一服务区两个架次中的一对箱体。
        for first_idx, first in enumerate(open_batches):
            for second_idx in range(first_idx + 1, len(open_batches)):
                second = open_batches[second_idx]
                if first.service_area_id != second.service_area_id:
                    continue
                for first_box_id in tuple(first.box_ids):
                    for second_box_id in tuple(second.box_ids):
                        first_box = boxes_by_id[first_box_id]
                        second_box = boxes_by_id[second_box_id]
                        candidate_open = _copy_open(open_batches)
                        candidate_open[first_idx].box_ids.remove(first_box_id)
                        candidate_open[first_idx].box_ids.append(second_box_id)
                        candidate_open[first_idx].mass_kg += second_box.mass_kg - first_box.mass_kg
                        candidate_open[first_idx].volume_m3 += second_box.volume_m3 - first_box.volume_m3
                        candidate_open[second_idx].box_ids.remove(second_box_id)
                        candidate_open[second_idx].box_ids.append(first_box_id)
                        candidate_open[second_idx].mass_kg += first_box.mass_kg - second_box.mass_kg
                        candidate_open[second_idx].volume_m3 += first_box.volume_m3 - second_box.volume_m3
                        if not all(
                            _open_is_feasible(item, evaluator) for item in candidate_open
                        ):
                            continue
                        candidate = _solution_from_batches(
                            evaluator.evaluate_open(candidate_open),
                            method_name,
                            complete_search=False,
                        )
                        if _objective(candidate) < _objective(best):
                            best = candidate
        if _objective(best) >= _objective(current):
            return current
        current = best
    return current


def _open_is_feasible(batch: _OpenBatch, evaluator: BatchEvaluator) -> bool:
    uav = evaluator.uav_types[batch.uav_type_id]
    safe = evaluator.safe_payloads[(batch.uav_type_id, batch.service_area_id)]
    if batch.mass_kg > safe + 1e-8 or batch.volume_m3 > uav.volume_capacity_m3 + 1e-8:
        return False
    energy = round_trip_energy_kwh(
        evaluator.provider,
        uav,
        evaluator.routes[batch.service_area_id],
        batch.mass_kg,
    )
    return energy <= (1.0 - uav.reserve_ratio) * uav.usable_energy_kwh + 1e-8


def _copy_open(batches: list[_OpenBatch]) -> list[_OpenBatch]:
    return [
        _OpenBatch(
            item.service_area_id,
            item.uav_type_id,
            list(item.box_ids),
            item.mass_kg,
            item.volume_m3,
        )
        for item in batches
    ]
