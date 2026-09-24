"""问题一的求解编排：物理量先行，FFD 基线先行，改进方法可选。"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

from .batching import BatchEvaluator, ffd_baseline, local_search_improve
from .energy_model import EnergyProvider
from .exceptions import InfeasibleProblemError
from .milp_solver import MILPUnavailable, solve_all_milp
from .models import (
    CargoBox,
    PayloadResult,
    RouteGeometry,
    Solution,
    UAVType,
)
from .payload_solver import max_safe_payload
from .validation import validate_solution


@dataclass(frozen=True)
class Q1Run:
    payload_results: tuple[PayloadResult, ...]
    baseline: Solution
    local_search: Solution
    milp: Solution | None
    milp_local_search: Solution | None
    validations: dict[str, dict]
    notes: tuple[str, ...] = ()


def _safe_payload_map(
    results: Iterable[PayloadResult],
) -> dict[tuple[str, str], float]:
    return {
        (result.uav_type_id, result.service_area_id): result.safe_payload_kg
        for result in results
    }


def solve_q1(
    boxes: Iterable[CargoBox],
    uav_types: dict[str, UAVType],
    routes: dict[str, RouteGeometry],
    provider: EnergyProvider,
    *,
    range_constraint: bool = True,
    try_milp: bool = True,
    milp_time_limit_s: float = 120.0,
    local_search_iterations: int = 200,
) -> Q1Run:
    """运行问题一的最小完整链。

    先计算所有安全载荷，再运行并验证 FFD 基线。只有基线通过后才
    进入局部搜索和可选 MILP，不把改进算法的输出当作物理模型验证。
    """

    payload_results = tuple(
        max_safe_payload(
            provider,
            uav_types[type_id],
            routes[area_id],
            range_constraint=range_constraint,
        )
        for type_id in sorted(uav_types)
        for area_id in sorted(routes)
    )
    safe_payloads = _safe_payload_map(payload_results)
    if any(not result.feasible_at_zero_payload for result in payload_results):
        bad = [
            f"{result.uav_type_id}/{result.service_area_id}"
            for result in payload_results
            if not result.feasible_at_zero_payload
        ]
        raise InfeasibleProblemError(f"零载荷也不可行的机型/服务区: {bad}")

    evaluator = BatchEvaluator(provider, routes, uav_types, safe_payloads)
    baseline = ffd_baseline(boxes, evaluator)
    baseline_validation = validate_solution(boxes, baseline, evaluator)
    if not baseline_validation["passed"]:
        raise InfeasibleProblemError(
            f"FFD 基线验证失败: {baseline_validation['errors']}"
        )

    local = local_search_improve(
        boxes,
        evaluator,
        baseline,
        max_iterations=local_search_iterations,
    )
    local_validation = validate_solution(boxes, local, evaluator)

    milp = None
    milp_local = None
    notes: list[str] = []
    if not local_validation["passed"]:
        raise InfeasibleProblemError(
            f"局部搜索结果验证失败: {local_validation['errors']}"
        )
    if try_milp:
        try:
            milp = solve_all_milp(
                boxes,
                evaluator,
                time_limit_s=milp_time_limit_s,
            )
            milp_validation = validate_solution(boxes, milp, evaluator)
            if not milp_validation["passed"]:
                notes.append("MILP 解未通过完整验证，已从最终候选中剔除")
                milp = None
            else:
                milp_local = local_search_improve(
                    boxes,
                    evaluator,
                    milp,
                    max_iterations=local_search_iterations,
                    method_name="local search from MILP",
                )
                if not validate_solution(boxes, milp_local, evaluator)["passed"]:
                    notes.append("MILP 后局部搜索解未通过验证，已从最终候选中剔除")
                    milp_local = None
        except MILPUnavailable as exc:
            notes.append(f"MILP 对照不可用: {exc}")

    validations = {
        "ffd_baseline": baseline_validation,
        "local_search": local_validation,
    }
    if milp is not None:
        validations["milp"] = validate_solution(boxes, milp, evaluator)
    if milp_local is not None:
        validations["milp_local_search"] = validate_solution(
            boxes, milp_local, evaluator
        )
    return Q1Run(
        payload_results=payload_results,
        baseline=baseline,
        local_search=local,
        milp=milp,
        milp_local_search=milp_local,
        validations=validations,
        notes=tuple(notes),
    )
