"""最大安全载荷求解。"""

from __future__ import annotations

from dataclasses import replace
from typing import Callable

from .energy_model import (
    EnergyProvider,
    equivalent_range_m,
    round_trip_energy_kwh,
)
from .exceptions import InfeasibleProblemError
from .models import PayloadResult, RouteGeometry, UAVType


def is_payload_feasible(
    provider: EnergyProvider,
    uav: UAVType,
    route: RouteGeometry,
    payload_kg: float,
    *,
    range_constraint: bool = True,
    tolerance: float = 1e-9,
) -> tuple[bool, float, float]:
    """返回 (可行, 往返能耗, 允许任务能量)。"""

    energy = round_trip_energy_kwh(provider, uav, route, payload_kg)
    allowed = (1.0 - uav.reserve_ratio) * uav.usable_energy_kwh
    distance = route.outbound.distance_m + route.inbound.distance_m
    range_ok = (
        not range_constraint
        or distance <= equivalent_range_m(uav, payload_kg) + tolerance
    )
    return energy <= allowed + tolerance and range_ok, energy, allowed


def max_safe_payload(
    provider: EnergyProvider,
    uav: UAVType,
    route: RouteGeometry,
    *,
    range_constraint: bool = True,
    iterations: int = 70,
) -> PayloadResult:
    """在 [0,Q_g] 上计算最大可行载荷。

    题目给出的范围和能耗规则都使可行性随载荷增加而不利；函数仍会
    在端点和二分结果上复核，避免把单调性当成未检查的事实。
    """

    low = 0.0
    high = uav.max_payload_kg
    zero_ok, zero_energy, allowed = is_payload_feasible(
        provider, uav, route, 0.0, range_constraint=range_constraint
    )
    if not zero_ok:
        return PayloadResult(
            uav_type_id=uav.type_id,
            service_area_id=route.service_area_id,
            safe_payload_kg=0.0,
            max_payload_kg=uav.max_payload_kg,
            round_trip_energy_kwh=zero_energy,
            allowed_energy_kwh=allowed,
            round_trip_distance_m=route.outbound.distance_m + route.inbound.distance_m,
            range_at_safe_payload_m=equivalent_range_m(uav, 0.0),
            feasible_at_zero_payload=False,
            search_method="endpoint-check",
            notes=("零载荷往返已经不满足能量或航程约束",),
        )

    full_ok, full_energy, _ = is_payload_feasible(
        provider, uav, route, high, range_constraint=range_constraint
    )
    if full_ok:
        return PayloadResult(
            uav_type_id=uav.type_id,
            service_area_id=route.service_area_id,
            safe_payload_kg=high,
            max_payload_kg=uav.max_payload_kg,
            round_trip_energy_kwh=full_energy,
            allowed_energy_kwh=allowed,
            round_trip_distance_m=route.outbound.distance_m + route.inbound.distance_m,
            range_at_safe_payload_m=equivalent_range_m(uav, high),
            feasible_at_zero_payload=True,
            search_method="endpoint-check",
        )

    for _ in range(iterations):
        mid = (low + high) / 2.0
        ok, _, _ = is_payload_feasible(
            provider, uav, route, mid, range_constraint=range_constraint
        )
        if ok:
            low = mid
        else:
            high = mid

    final_ok, final_energy, _ = is_payload_feasible(
        provider, uav, route, low, range_constraint=range_constraint
    )
    if not final_ok:
        raise InfeasibleProblemError(
            f"二分结果未通过端点复核: {uav.type_id}/{route.service_area_id}"
        )
    return PayloadResult(
        uav_type_id=uav.type_id,
        service_area_id=route.service_area_id,
        safe_payload_kg=low,
        max_payload_kg=uav.max_payload_kg,
        round_trip_energy_kwh=final_energy,
        allowed_energy_kwh=allowed,
        round_trip_distance_m=route.outbound.distance_m + route.inbound.distance_m,
        range_at_safe_payload_m=equivalent_range_m(uav, low),
        feasible_at_zero_payload=True,
        search_method="bisection-with-endpoint-check",
        notes=(
            "正式报告需由实际能耗数据验证载荷—能耗单调性；否则改用网格/枚举。",
        ),
    )


def payload_matrix(
    provider: EnergyProvider,
    uav_types: dict[str, UAVType],
    routes: dict[str, RouteGeometry],
    *,
    range_constraint: bool = True,
) -> tuple[PayloadResult, ...]:
    results: list[PayloadResult] = []
    for type_id in sorted(uav_types):
        for area_id in sorted(routes):
            results.append(
                max_safe_payload(
                    provider,
                    uav_types[type_id],
                    routes[area_id],
                    range_constraint=range_constraint,
                )
            )
    return tuple(results)


def override_reserve(
    uav_types: dict[str, UAVType],
    reserve_by_type: dict[str, float] | float,
) -> dict[str, UAVType]:
    """为敏感性分析生成新视图，不修改原始输入。"""

    result: dict[str, UAVType] = {}
    for type_id, uav in uav_types.items():
        rho = (
            reserve_by_type
            if isinstance(reserve_by_type, (int, float))
            else reserve_by_type[type_id]
        )
        result[type_id] = replace(uav, reserve_ratio=float(rho))
    return result
