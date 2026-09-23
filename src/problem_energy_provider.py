"""问题一的透明参数化能耗模型。

题目附录 2 明确给出

    E_gij(q) = E_gij^hor(q) + E_gij^up(q)

以及下降附加能耗不单独计算，但没有给出两个子项的展开式。这个模块
因此不是“题面官方公式”的冒充，而是一个可审计的参考模型 A：

1. 用题目给出的等效航程和可用电量定义水平巡航平均能耗强度：
   E_hor = d * E_g^use / L_g(q)。这样在距离等于该载荷下的标准航程时，
   水平巡航消耗一组可用电量。
2. 用输入表中的空载总质量、当前载荷和爬升能耗效率计算重力势能附加项：
   E_up = (m_empty + q) * g * h_up / (eta_up * 3.6e6)。
3. 按题目规则不添加下降附加能耗。

该选择只使用题目数据表中实际存在的参数，并把假设显式暴露给结果与
敏感性分析。正式报告必须把它称为“参数化参考模型 A”，并与题目官方
补充说明（若后续提供）复核；不能把它写成题面已经给出的唯一公式。
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from .energy_model import equivalent_range_m
from .exceptions import EnergySpecificationError
from .models import LegGeometry, UAVType


GRAVITY_MPS2 = 9.80665
JOULE_PER_KWH = 3.6e6


@dataclass(frozen=True)
class TaskParameterizedEnergyProvider:
    """由题目附录口径和真实输入字段组成的显式能耗适配器。"""

    source: str = (
        "reference-model-A-v1; task Appendix 2 plus "
        "运输无人机数据.xlsx; E_hor=d*Euse/L(q), "
        "E_up=(m_empty+q)*g*h_up/(eta_up*3.6e6); descent add-on=0"
    )

    def horizontal_kwh(
        self,
        uav: UAVType,
        leg: LegGeometry,
        payload_kg: float,
    ) -> float:
        range_m = equivalent_range_m(uav, payload_kg)
        if range_m <= 0 or not math.isfinite(range_m):
            raise EnergySpecificationError(
                f"机型 {uav.type_id} 的等效航程无效: {range_m}"
            )
        value = leg.distance_m * uav.usable_energy_kwh / range_m
        if not math.isfinite(value) or value < 0:
            raise EnergySpecificationError(
                f"机型 {uav.type_id} 的水平巡航能耗无效: {value}"
            )
        return value

    def climb_kwh(
        self,
        uav: UAVType,
        leg: LegGeometry,
        payload_kg: float,
    ) -> float:
        if leg.climb_m <= 0:
            return 0.0
        if uav.empty_mass_kg <= 0:
            raise EnergySpecificationError(
                f"机型 {uav.type_id} 缺少正的含电池空载总质量"
            )
        if not 0 < uav.climb_efficiency <= 1:
            raise EnergySpecificationError(
                f"机型 {uav.type_id} 的爬升能耗效率必须位于 (0,1]"
            )
        value = (
            (uav.empty_mass_kg + payload_kg)
            * GRAVITY_MPS2
            * leg.climb_m
            / (uav.climb_efficiency * JOULE_PER_KWH)
        )
        if not math.isfinite(value) or value < 0:
            raise EnergySpecificationError(
                f"机型 {uav.type_id} 的爬升附加能耗无效: {value}"
            )
        return value


def build_provider(uav_types: dict[str, UAVType]) -> TaskParameterizedEnergyProvider:
    """供 src.run_q1 通过 --energy-provider 显式加载。"""

    if not uav_types:
        raise EnergySpecificationError("能耗适配器未收到运输机型")
    for type_id, uav in uav_types.items():
        if uav.empty_mass_kg <= 0 or uav.climb_efficiency <= 0:
            raise EnergySpecificationError(
                f"机型 {type_id} 缺少参考模型 A 所需的空载质量/爬升效率"
            )
    return TaskParameterizedEnergyProvider()
