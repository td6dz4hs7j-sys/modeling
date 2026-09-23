"""可选 MILP 组批改进。

MILP 只负责在质量/体积/安全载荷容量下最小化架次数；解出后仍用
题目能耗函数重新评价，并交给局部搜索比较能耗和时间。没有 scipy
或求解超时不会伪造结果，调用方应保留 FFD 基线并记录阻断原因。
"""

from __future__ import annotations

from typing import Iterable

from .batching import BatchEvaluator, _OpenBatch, _solution_from_batches
from .exceptions import InfeasibleProblemError
from .models import CargoBox, Solution


class MILPUnavailable(RuntimeError):
    """MILP 求解器不可用或没有返回可行解。"""


def solve_area_milp(
    boxes: Iterable[CargoBox],
    evaluator: BatchEvaluator,
    area_id: str,
    *,
    time_limit_s: float = 120.0,
) -> tuple[tuple[_OpenBatch, ...], bool]:
    """对一个固定服务区建立多类型、多容量 0-1 组批模型。"""

    boxes = tuple(box for box in boxes if box.service_area_id == area_id)
    if not boxes:
        return (), True
    try:
        import numpy as np
        from scipy.optimize import Bounds, LinearConstraint, milp
        from scipy.sparse import lil_matrix
    except ImportError as exc:
        raise MILPUnavailable("MILP 对照需要 scipy.optimize.milp") from exc

    type_ids = sorted(evaluator.uav_types)
    n_boxes = len(boxes)
    x_index: dict[tuple[int, int, str], int] = {}
    y_index: dict[tuple[int, str], int] = {}
    variable_count = 0
    for slot in range(n_boxes):
        for type_id in type_ids:
            y_index[(slot, type_id)] = variable_count
            variable_count += 1
            for box_index, box in enumerate(boxes):
                x_index[(box_index, slot, type_id)] = variable_count
                variable_count += 1

    rows: list[tuple[str, int, str | None]] = []
    for box_index in range(n_boxes):
        rows.append(("assignment", box_index, None))
    for slot in range(n_boxes):
        for type_id in type_ids:
            rows.append(("mass", slot, type_id))
            rows.append(("volume", slot, type_id))
    matrix = lil_matrix((len(rows), variable_count), dtype=float)
    lower = np.full(len(rows), -np.inf, dtype=float)
    upper = np.full(len(rows), np.inf, dtype=float)
    row_number = 0

    for box_index in range(n_boxes):
        for slot in range(n_boxes):
            for type_id in type_ids:
                matrix[row_number, x_index[(box_index, slot, type_id)]] = 1.0
        lower[row_number] = upper[row_number] = 1.0
        row_number += 1

    upper_bounds = np.ones(variable_count, dtype=float)
    c = np.zeros(variable_count, dtype=float)
    for slot in range(n_boxes):
        for type_id in type_ids:
            y = y_index[(slot, type_id)]
            c[y] = 1.0
            uav = evaluator.uav_types[type_id]
            capacity = evaluator.safe_payloads[(type_id, area_id)]
            for box_index, box in enumerate(boxes):
                x = x_index[(box_index, slot, type_id)]
                if (
                    box.mass_kg > capacity + 1e-9
                    or box.volume_m3 > uav.volume_capacity_m3 + 1e-9
                    or not evaluator.can_start(box, type_id)
                ):
                    upper_bounds[x] = 0.0
                mass_row = n_boxes + 2 * (slot * len(type_ids) + type_ids.index(type_id))
                volume_row = mass_row + 1
                matrix[mass_row, x] = box.mass_kg
                matrix[volume_row, x] = box.volume_m3
            matrix[mass_row, y] = -capacity
            matrix[volume_row, y] = -uav.volume_capacity_m3
            upper[mass_row] = 0.0
            upper[volume_row] = 0.0

    result = milp(
        c=c,
        integrality=np.ones(variable_count, dtype=int),
        bounds=Bounds(np.zeros(variable_count), upper_bounds),
        constraints=LinearConstraint(matrix.tocsr(), lower, upper),
        options={"time_limit": time_limit_s, "presolve": True},
    )
    if result.x is None or result.status not in {0, 1}:
        raise MILPUnavailable(
            f"MILP 未返回可用解，status={result.status}, message={result.message}"
        )

    open_batches: list[_OpenBatch] = []
    for slot in range(n_boxes):
        for type_id in type_ids:
            if result.x[y_index[(slot, type_id)]] < 0.5:
                continue
            selected = [
                boxes[box_index]
                for box_index in range(n_boxes)
                if result.x[x_index[(box_index, slot, type_id)]] > 0.5
            ]
            if not selected:
                continue
            open_batches.append(
                _OpenBatch(
                    service_area_id=area_id,
                    uav_type_id=type_id,
                    box_ids=[box.box_id for box in selected],
                    mass_kg=sum(box.mass_kg for box in selected),
                    volume_m3=sum(box.volume_m3 for box in selected),
                )
            )
    if sum(len(item.box_ids) for item in open_batches) != n_boxes:
        raise InfeasibleProblemError(
            f"MILP 解的箱体覆盖数不正确: {area_id}"
        )
    return tuple(open_batches), result.status == 0


def solve_all_milp(
    boxes: Iterable[CargoBox],
    evaluator: BatchEvaluator,
    *,
    time_limit_s: float = 120.0,
) -> Solution:
    areas = sorted({box.service_area_id for box in boxes})
    open_batches: list[_OpenBatch] = []
    complete_search = True
    for area_id in areas:
        area_batches, area_complete = solve_area_milp(
            boxes, evaluator, area_id, time_limit_s=time_limit_s
        )
        open_batches.extend(area_batches)
        complete_search = complete_search and area_complete
    batches = evaluator.evaluate_open(open_batches)
    return _solution_from_batches(
        batches,
        "MILP minimum-sortie",
        complete_search=complete_search,
        notes=(
            ()
            if complete_search
            else (
                "至少一个服务区的 MILP 在时间上限内返回可行解，"
                "未证明架次数最优；结果仍经过完整物理约束验证。",
            )
        ),
    )
