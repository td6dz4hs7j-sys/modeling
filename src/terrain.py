"""节点—DEM 几何计算。

题目规定采用两节点水平直线，并把直线所经过 DEM 像元的最高地面高程
上方 50 m 作为巡航海拔。本模块只实现这一规定，不做路径规划。
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from .exceptions import InputContractError
from .models import LegGeometry, Node, RouteGeometry


@dataclass
class DEM:
    """支持 GeoTIFF/rasterio、ESRI ASCII Grid 和简单 NPZ 的只读 DEM。"""

    path: Path
    _dataset: object | None = None
    _ascii: tuple[dict[str, float], list[list[float]]] | None = None
    _npz: object | None = None

    @classmethod
    def open(cls, path: str | Path) -> "DEM":
        dem = cls(Path(path).resolve())
        suffix = dem.path.suffix.lower()
        if suffix in {".tif", ".tiff", ".img"}:
            try:
                import rasterio
            except ImportError as exc:
                raise InputContractError(
                    "DEM 是栅格文件，读取需要 rasterio；请按环境检查结果安装或启用"
                ) from exc
            dem._dataset = rasterio.open(dem.path)
            if dem._dataset.count < 1:
                raise InputContractError(f"DEM 没有可读取波段: {dem.path}")
        elif suffix == ".asc":
            dem._ascii = _read_ascii_grid(dem.path)
        elif suffix == ".npz":
            try:
                import numpy as np
                dem._npz = np.load(dem.path)
            except Exception as exc:
                raise InputContractError(f"无法读取 DEM NPZ: {dem.path}") from exc
        else:
            raise InputContractError(f"不支持的 DEM 格式: {dem.path.suffix}")
        return dem

    def close(self) -> None:
        if self._dataset is not None and hasattr(self._dataset, "close"):
            self._dataset.close()
        if self._npz is not None and hasattr(self._npz, "close"):
            self._npz.close()

    def __enter__(self) -> "DEM":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def sample(self, longitude_deg: float, latitude_deg: float) -> float:
        if self._dataset is not None:
            return _sample_rasterio(
                self._dataset, longitude_deg, latitude_deg, self.path
            )
        if self._ascii is not None:
            header, grid = self._ascii
            return _sample_ascii(header, grid, longitude_deg, latitude_deg, self.path)
        if self._npz is not None:
            return _sample_npz(self._npz, longitude_deg, latitude_deg, self.path)
        raise InputContractError(f"DEM 未初始化: {self.path}")

    def segment_max_ground(
        self,
        start: Node,
        end: Node,
        *,
        spacing_m: float = 30.0,
    ) -> float:
        distance = wgs84_distance_m(start, end)
        n = max(2, int(math.ceil(distance / spacing_m)) + 1)
        maximum = -math.inf
        for k in range(n):
            fraction = k / (n - 1)
            lon = start.longitude_deg + fraction * (
                end.longitude_deg - start.longitude_deg
            )
            lat = start.latitude_deg + fraction * (
                end.latitude_deg - start.latitude_deg
            )
            maximum = max(maximum, self.sample(lon, lat))
        if not math.isfinite(maximum):
            raise InputContractError(
                f"航段 {start.node_id}->{end.node_id} 没有可用 DEM 高程"
            )
        return maximum


def _read_ascii_grid(path: Path) -> tuple[dict[str, float], list[list[float]]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    if len(lines) < 7:
        raise InputContractError(f"ESRI ASCII DEM 行数不足: {path}")
    header: dict[str, float] = {}
    for line in lines[:6]:
        key, value = line.split(maxsplit=1)
        header[key.lower()] = float(value)
    required = {"ncols", "nrows", "cellsize"}
    if not required.issubset(header):
        raise InputContractError(f"ASCII DEM 缺少头字段: {required - set(header)}")
    nrows = int(header["nrows"])
    grid: list[list[float]] = []
    for line in lines[6:]:
        if line.strip():
            grid.append([float(x) for x in line.split()])
    if len(grid) != nrows or any(len(row) != int(header["ncols"]) for row in grid):
        raise InputContractError(f"ASCII DEM 行列数与头字段不一致: {path}")
    return header, grid


def _sample_rasterio(dataset: object, lon: float, lat: float, path: Path) -> float:
    import numpy as np

    try:
        import rasterio
        from rasterio.warp import transform
        crs = getattr(dataset, "crs", None)
        if crs is None:
            raise InputContractError(f"DEM 没有 CRS，无法解释经纬度: {path}")
        if str(crs).upper() not in {"EPSG:4326", "OGC:CRS84"}:
            x, y = transform("EPSG:4326", crs, [lon], [lat])
            x, y = x[0], y[0]
        else:
            x, y = lon, lat
        row, col = dataset.index(x, y)
        if row < 0 or col < 0 or row >= dataset.height or col >= dataset.width:
            raise InputContractError(f"节点/航段超出 DEM 范围: ({lon}, {lat})")
        value = dataset.read(1, window=rasterio.windows.Window(col, row, 1, 1))[0, 0]
        nodata = getattr(dataset, "nodata", None)
        if nodata is not None and value == nodata:
            raise InputContractError(f"DEM 采样到 nodata: ({lon}, {lat})")
        if not np.isfinite(value):
            raise InputContractError(f"DEM 采样值不是有限数: ({lon}, {lat})")
        return float(value)
    except InputContractError:
        raise
    except Exception as exc:
        raise InputContractError(f"DEM 采样失败 {path}: ({lon}, {lat})") from exc


def _sample_ascii(
    header: dict[str, float],
    grid: list[list[float]],
    lon: float,
    lat: float,
    path: Path,
) -> float:
    # ASCII Grid 的坐标与节点坐标必须同一坐标系；题目配套说明负责确认这一点。
    cell = header["cellsize"]
    x0 = header.get("xllcorner", header.get("xllcenter"))
    y0 = header.get("yllcorner", header.get("yllcenter"))
    if x0 is None or y0 is None:
        raise InputContractError(f"ASCII DEM 缺少 xll/yll 坐标: {path}")
    col = int(math.floor((lon - x0) / cell))
    row_from_bottom = int(math.floor((lat - y0) / cell))
    row = int(header["nrows"]) - 1 - row_from_bottom
    if row < 0 or col < 0 or row >= len(grid) or col >= len(grid[0]):
        raise InputContractError(f"节点/航段超出 ASCII DEM 范围: ({lon}, {lat})")
    value = float(grid[row][col])
    nodata = header.get("nodata_value")
    if nodata is not None and value == nodata:
        raise InputContractError(f"ASCII DEM 采样到 nodata: ({lon}, {lat})")
    return value


def _sample_npz(npz: object, lon: float, lat: float, path: Path) -> float:
    try:
        import numpy as np
        x = np.asarray(npz["x"])
        y = np.asarray(npz["y"])
        z = np.asarray(npz["elevation"])
    except Exception as exc:
        raise InputContractError(
            f"NPZ DEM 必须包含 x、y、elevation 数组: {path}"
        ) from exc
    if z.ndim != 2 or x.ndim != 1 or y.ndim != 1 or z.shape != (len(y), len(x)):
        raise InputContractError(f"NPZ DEM 数组形状不一致: {path}")
    col = int(np.argmin(np.abs(x - lon)))
    row = int(np.argmin(np.abs(y - lat)))
    value = float(z[row, col])
    if not np.isfinite(value):
        raise InputContractError(f"NPZ DEM 采样值不是有限数: ({lon}, {lat})")
    return value


def wgs84_distance_m(start: Node, end: Node) -> float:
    """使用 WGS84 测地线计算水平距离；不以平面近似替代。"""

    try:
        from pyproj import Geod
    except ImportError as exc:
        raise InputContractError(
            "经纬度距离计算需要 pyproj；请按环境检查结果安装或启用"
        ) from exc
    geod = Geod(ellps="WGS84")
    _, _, distance = geod.inv(
        start.longitude_deg,
        start.latitude_deg,
        end.longitude_deg,
        end.latitude_deg,
    )
    if not math.isfinite(distance) or distance <= 0:
        raise InputContractError(
            f"节点 {start.node_id}->{end.node_id} 的水平距离无效: {distance}"
        )
    return float(distance)


def build_routes(
    nodes: dict[str, Node],
    dem: DEM,
    *,
    service_area_ids: Iterable[str] | None = None,
) -> dict[str, RouteGeometry]:
    center = nodes["O01"]
    areas = sorted(
        service_area_ids
        if service_area_ids is not None
        else [node_id for node_id in nodes if node_id.startswith("S")]
    )
    center_ground = dem.sample(center.longitude_deg, center.latitude_deg)
    routes: dict[str, RouteGeometry] = {}
    for area_id in areas:
        if area_id not in nodes:
            raise InputContractError(f"服务区不在节点表中: {area_id}")
        target = nodes[area_id]
        target_ground = dem.sample(target.longitude_deg, target.latitude_deg)
        max_ground = dem.segment_max_ground(center, target)
        cruise_altitude = max_ground + 50.0
        center_work = center_ground
        target_work = target_ground + 30.0
        distance = wgs84_distance_m(center, target)
        outbound = LegGeometry(
            start_id=center.node_id,
            end_id=target.node_id,
            distance_m=distance,
            climb_m=max(0.0, cruise_altitude - center_work),
            descent_m=max(0.0, cruise_altitude - target_work),
            cruise_altitude_m=cruise_altitude,
            start_work_altitude_m=center_work,
            end_work_altitude_m=target_work,
            max_ground_elevation_m=max_ground,
        )
        inbound = LegGeometry(
            start_id=target.node_id,
            end_id=center.node_id,
            distance_m=distance,
            climb_m=max(0.0, cruise_altitude - target_work),
            descent_m=max(0.0, cruise_altitude - center_work),
            cruise_altitude_m=cruise_altitude,
            start_work_altitude_m=target_work,
            end_work_altitude_m=center_work,
            max_ground_elevation_m=max_ground,
        )
        routes[area_id] = RouteGeometry(area_id, outbound, inbound)
    return routes
