"""题目问题一的时间、等效航程和能耗接口。

题目 DOCX 只展开了能耗分解
E = E_hor + E_up，没有给出两个子项的具体表达式。因而本模块拒绝
内置默认功率或效率，正式运行必须显式注入由题目附件/补充说明核验过的
EnergyProvider。
"""

from __future__ import annotations

import importlib
import math
from dataclasses import dataclass
from types import ModuleType
from typing import Protocol

from .exceptions import EnergySpecificationError, InputContractError
from .models import LegGeometry, RouteGeometry, UAVType


class EnergyProvider(Protocol):
    """能耗适配器的最小接口。

    实现必须返回 kWh，并明确接受当前航段有效载荷、水平距离和爬升高度。
    下降附加能耗由题目规则取 0，因此没有 descent_energy 方法。
    """

    source: str

    def horizontal_kwh(
        self, uav: UAVType, leg: LegGeometry, payload_kg: float
    ) -> float:
        ...

    def climb_kwh(
        self, uav: UAVType, leg: LegGeometry, payload_kg: float
    ) -> float:
        ...


@dataclass(frozen=True)
class LegEnergy:
    horizontal_kwh: float
    climb_kwh: float

    @property
    def total_kwh(self) -> float:
        return self.horizontal_kwh + self.climb_kwh


def load_energy_provider(module_name: str, uav_types: dict[str, UAVType]) -> EnergyProvider:
    """从显式模块加载能耗适配器，不猜测模块或公式。"""

    if not module_name:
        raise EnergySpecificationError(
            "未提供能耗适配器。请核验题目附件/补充规则后，通过 "
            "--energy-provider 指定实现了 build_provider(uav_types) 的模块。"
        )
    module: ModuleType = importlib.import_module(module_name)
    builder = getattr(module, "build_provider", None)
    if builder is None or not callable(builder):
        raise EnergySpecificationError(
            f"能耗模块 {module_name} 必须显式提供 build_provider(uav_types)"
        )
    provider = builder(uav_types)
    for name in ("horizontal_kwh", "climb_kwh"):
        if not callable(getattr(provider, name, None)):
            raise EnergySpecificationError(
                f"能耗适配器缺少可调用方法 {name}"
            )
    if not getattr(provider, "source", None):
        raise EnergySpecificationError("能耗适配器必须提供可追溯的 source 字段")
    return provider


def equivalent_range_m(uav: UAVType, payload_kg: float) -> float:
    """题目附录 2 的等效航程公式。"""

    if not 0 <= payload_kg <= uav.max_payload_kg:
        raise InputContractError(
            f"机型 {uav.type_id} 的载荷 {payload_kg} 不在 [0,Q_g] 内"
        )
    fraction = payload_kg / uav.max_payload_kg
    return uav.empty_range_m - (
        uav.empty_range_m - uav.full_range_m
    ) * fraction ** 1.5


def leg_time_s(uav: UAVType, leg: LegGeometry) -> float:
    value = (
        leg.climb_m / uav.climb_speed_mps
        + leg.distance_m / uav.cruise_speed_mps
        + leg.descent_m / uav.descent_speed_mps
    )
    if not math.isfinite(value) or value <= 0:
        raise InputContractError(
            f"机型 {uav.type_id} 航段 {leg.start_id}->{leg.end_id} 时间无效: {value}"
        )
    return value


def leg_energy_kwh(
    provider: EnergyProvider,
    uav: UAVType,
    leg: LegGeometry,
    payload_kg: float,
) -> LegEnergy:
    if not 0 <= payload_kg <= uav.max_payload_kg:
        raise InputContractError(
            f"机型 {uav.type_id} 航段载荷超出范围: {payload_kg}"
        )
    horizontal = float(provider.horizontal_kwh(uav, leg, payload_kg))
    climb = float(provider.climb_kwh(uav, leg, payload_kg))
    if not math.isfinite(horizontal) or not math.isfinite(climb):
        raise EnergySpecificationError(
            f"能耗适配器 {provider.source} 返回非有限值"
        )
    if horizontal < 0 or climb < 0:
        raise EnergySpecificationError(
            f"能耗适配器 {provider.source} 返回负能耗"
        )
    return LegEnergy(horizontal, climb)


def round_trip_energy_kwh(
    provider: EnergyProvider,
    uav: UAVType,
    route: RouteGeometry,
    outbound_payload_kg: float,
) -> float:
    outbound = leg_energy_kwh(provider, uav, route.outbound, outbound_payload_kg)
    inbound = leg_energy_kwh(provider, uav, route.inbound, 0.0)
    value = outbound.total_kwh + inbound.total_kwh
    allowed = (1.0 - uav.reserve_ratio) * uav.usable_energy_kwh
    if value < 0 or not math.isfinite(value):
        raise EnergySpecificationError(f"往返能耗无效: {value}")
    if not math.isfinite(allowed) or allowed <= 0:
        raise InputContractError(
            f"机型 {uav.type_id} 的可用能量与余量给出非正可用任务能量"
        )
    return value


def round_trip_time_s(uav: UAVType, route: RouteGeometry) -> float:
    return leg_time_s(uav, route.outbound) + leg_time_s(uav, route.inbound)
