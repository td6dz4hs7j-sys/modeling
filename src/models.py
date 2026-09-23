"""问题一的共享数据结构。

这些对象只承载题目数据和已计算的几何量，不在这里提供未经题目或文献
核验的默认物理参数。
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Optional


@dataclass(frozen=True)
class Node:
    node_id: str
    longitude_deg: float
    latitude_deg: float


@dataclass(frozen=True)
class CargoBox:
    box_id: str
    service_area_id: str
    mass_kg: float
    volume_m3: float
    deadline_s: Optional[float] = None


@dataclass(frozen=True)
class UAVType:
    type_id: str
    max_payload_kg: float
    empty_range_m: float
    full_range_m: float
    climb_speed_mps: float
    cruise_speed_mps: float
    descent_speed_mps: float
    usable_energy_kwh: float
    reserve_ratio: float
    volume_capacity_m3: float
    metadata: dict[str, Any] = field(default_factory=dict)
    # These fields are present in the supplied transport-UAV workbook.  They
    # are optional at the shared data-structure level so the software-only
    # self-test can continue to use its deliberately synthetic provider.
    empty_mass_kg: float = 0.0
    climb_efficiency: float = 0.0
    descent_efficiency: float = 0.0
    # Q1 operation-time parameters supplied in 运输无人机数据.xlsx.  They
    # are kept separate from flight time so the two reporting conventions
    # cannot be mixed accidentally.
    preparation_time_s: float = 0.0
    loading_time_per_box_s: float = 0.0
    handoff_base_time_s: float = 0.0
    handoff_time_per_box_s: float = 0.0


@dataclass(frozen=True)
class LegGeometry:
    start_id: str
    end_id: str
    distance_m: float
    climb_m: float
    descent_m: float
    cruise_altitude_m: float
    start_work_altitude_m: float
    end_work_altitude_m: float
    max_ground_elevation_m: float


@dataclass(frozen=True)
class RouteGeometry:
    service_area_id: str
    outbound: LegGeometry
    inbound: LegGeometry


@dataclass(frozen=True)
class PayloadResult:
    uav_type_id: str
    service_area_id: str
    safe_payload_kg: float
    max_payload_kg: float
    round_trip_energy_kwh: float
    allowed_energy_kwh: float
    round_trip_distance_m: float
    range_at_safe_payload_m: float
    feasible_at_zero_payload: bool
    search_method: str
    notes: tuple[str, ...] = ()


@dataclass(frozen=True)
class Batch:
    batch_id: str
    service_area_id: str
    uav_type_id: str
    box_ids: tuple[str, ...]
    mass_kg: float
    volume_m3: float
    flight_time_s: float
    work_time_s: float
    energy_kwh: float
    return_soc_ratio: float


@dataclass(frozen=True)
class Solution:
    batches: tuple[Batch, ...]
    total_sorties: int
    total_energy_kwh: float
    total_time_s: float
    method: str
    complete_search: bool = True
    notes: tuple[str, ...] = ()


@dataclass(frozen=True)
class InputBundle:
    nodes: dict[str, Node]
    boxes: tuple[CargoBox, ...]
    uav_types: dict[str, UAVType]
    source_files: tuple[str, ...]
    dem_path: str
