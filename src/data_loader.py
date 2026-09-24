"""读取问题一的原始 XLSX/DEM 数据并执行输入合同校验。

读取采用 header=False 的等价策略：先逐行寻找包含必需字段的表头，
再从表头下一行开始读取，避免把第一条数据误当列名。
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Sequence

from .exceptions import InputContractError, MissingInputError
from .models import CargoBox, InputBundle, Node, UAVType


BASE_DIRNAME = "无人机应急物资运输基础数据"
GEO_DIRNAME = "镇龙乡地理空间数据"


@dataclass(frozen=True)
class Table:
    path: Path
    sheet_name: str
    header_row: int
    headers: tuple[Any, ...]
    rows: tuple[tuple[Any, ...], ...]


def _norm(value: Any) -> str:
    text = "" if value is None else str(value)
    return re.sub(r"[\s\u3000_\-（）()［］\[\]：:，,。./]", "", text).lower()


def _text(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip()


def _number(value: Any, *, field: str, row: int) -> float:
    if value is None or (isinstance(value, str) and not value.strip()):
        raise InputContractError(f"第 {row} 行字段 {field} 为空")
    if isinstance(value, str):
        value = value.strip().replace(",", "")
        if value.endswith("%"):
            value = value[:-1].strip()
            try:
                return float(value) / 100.0
            except ValueError as exc:
                raise InputContractError(
                    f"第 {row} 行字段 {field} 不是数值: {value!r}"
                ) from exc
    try:
        result = float(value)
    except (TypeError, ValueError) as exc:
        raise InputContractError(
            f"第 {row} 行字段 {field} 不是数值: {value!r}"
        ) from exc
    if not math.isfinite(result):
        raise InputContractError(f"第 {row} 行字段 {field} 不是有限数")
    return result


def _fraction(value: Any, header: Any, *, field: str, row: int) -> float:
    result = _number(value, field=field, row=row)
    header_norm = _norm(header)
    if "%" in str(header) or "百分" in header_norm:
        if result > 1:
            result /= 100.0
    if not 0 <= result < 1:
        raise InputContractError(
            f"第 {row} 行字段 {field} 必须是 [0,1) 比例，得到 {result}"
        )
    return result


def _canonical_node_id(value: Any) -> str:
    text = _text(value).upper().replace(" ", "")
    if text in {"O01", "001", "O1"}:
        return "O01"
    match = re.fullmatch(r"S0*(\d+)", text)
    if match:
        return f"S{int(match.group(1)):03d}"
    return text


def _canonical_area_id(value: Any) -> str:
    text = _canonical_node_id(value)
    if text == "O01":
        raise InputContractError("货箱服务区不能是 O01")
    if not text.startswith("S"):
        raise InputContractError(f"无法识别服务区编号: {value!r}")
    return text


def _find_column(headers: Sequence[Any], aliases: Sequence[str], *, table: str) -> int:
    normalized = [_norm(item) for item in headers]
    alias_norm = [_norm(item) for item in aliases]
    exact = [i for i, h in enumerate(normalized) if h in alias_norm]
    if len(exact) == 1:
        return exact[0]
    contains = [
        i for i, h in enumerate(normalized)
        if h and any(a and (a in h or h in a) for a in alias_norm)
    ]
    if len(contains) == 1:
        return contains[0]
    if not contains:
        raise InputContractError(
            f"{table} 缺少字段，候选名称为 {list(aliases)}；实际表头为 {list(headers)}"
        )
    raise InputContractError(
        f"{table} 字段映射不唯一，候选名称为 {list(aliases)}；实际表头为 {list(headers)}"
    )


def _find_optional_column(headers: Sequence[Any], aliases: Sequence[str]) -> int | None:
    normalized = [_norm(item) for item in headers]
    alias_norm = [_norm(item) for item in aliases]
    hits = [
        i for i, h in enumerate(normalized)
        if h and any(a and (a == h or a in h or h in a) for a in alias_norm)
    ]
    return hits[0] if len(hits) == 1 else None


def _read_tables(path: Path) -> list[Table]:
    try:
        import openpyxl
    except ImportError as exc:
        raise InputContractError(
            "读取 XLSX 需要 openpyxl；请按环境检查结果安装或启用该依赖"
        ) from exc

    workbook = openpyxl.load_workbook(path, data_only=True, read_only=True)
    tables: list[Table] = []
    for sheet in workbook.worksheets:
        raw_rows = [tuple(row) for row in sheet.iter_rows(values_only=True)]
        for header_idx, header in enumerate(raw_rows[:30]):
            nonempty = [item for item in header if item is not None and str(item).strip()]
            if len(nonempty) < 2:
                continue
            tables.append(
                Table(
                    path=path,
                    sheet_name=sheet.title,
                    header_row=header_idx,
                    headers=header,
                    rows=tuple(raw_rows[header_idx + 1 :]),
                )
            )
    if not tables:
        raise InputContractError(f"未在 XLSX 中找到可读取表头: {path}")
    return tables


def _choose_table(path: Path, required_aliases: Sequence[Sequence[str]]) -> Table:
    candidates: list[Table] = []
    errors: list[str] = []
    for table in _read_tables(path):
        try:
            for aliases in required_aliases:
                _find_column(table.headers, aliases, table=f"{path.name}/{table.sheet_name}")
            candidates.append(table)
        except InputContractError as exc:
            errors.append(str(exc))
    if len(candidates) == 1:
        return candidates[0]
    if not candidates:
        detail = errors[0] if errors else "无候选表"
        raise InputContractError(f"无法在 {path} 中定位目标表: {detail}")
    raise InputContractError(
        f"{path} 中有多个表同时满足字段合同，不能猜测应使用哪一个: "
        f"{[(t.sheet_name, t.header_row + 1) for t in candidates]}"
    )


def _data_rows(table: Table) -> Iterable[tuple[int, tuple[Any, ...]]]:
    for offset, row in enumerate(table.rows, start=table.header_row + 2):
        if any(item is not None and str(item).strip() for item in row):
            yield offset, row


def _locate(data_dir: Path, filename: str) -> Path:
    candidates = [
        data_dir / BASE_DIRNAME / filename,
        data_dir / filename,
        data_dir / "raw" / BASE_DIRNAME / filename,
        data_dir / "raw" / filename,
    ]
    candidates.extend(
        path for path in data_dir.rglob(filename) if path.is_file()
    )
    unique = tuple(dict.fromkeys(path.resolve() for path in candidates if path.is_file()))
    if len(unique) == 1:
        return unique[0]
    if len(unique) > 1:
        raise InputContractError(
            f"题目附件 {filename} 找到多个副本，不能猜测："
            + ", ".join(str(path) for path in unique)
        )
    raise MissingInputError(
        f"缺少题目附件 {filename}；已检查目录: {data_dir}"
    )


def _locate_dem(data_dir: Path) -> Path:
    all_candidates = [
        path for path in data_dir.rglob("*")
        if path.is_file()
        and path.suffix.lower() in {".tif", ".tiff", ".asc", ".npz", ".img"}
    ]
    if not all_candidates:
        raise MissingInputError(
            f"未找到 30 米 DEM 栅格；已递归检查目录 {data_dir}"
        )
    preferred = [
        path for path in all_candidates
        if any(token in path.stem.lower() for token in ("dem", "elev", "高程"))
    ]
    if len(preferred) == 1:
        return preferred[0]
    if len(all_candidates) == 1:
        return all_candidates[0]
    raise InputContractError(
        "DEM 栅格候选超过一个，不能猜测："
        + ", ".join(str(path) for path in all_candidates)
    )


def _load_nodes(path: Path) -> dict[str, Node]:
    aliases = [
        ("节点编号", "点位编号", "编号", "node_id", "id"),
        ("经度", "longitude", "lon", "x"),
        ("纬度", "latitude", "lat", "y"),
    ]
    matching_tables: list[Table] = []
    for table in _read_tables(path):
        try:
            for item in aliases:
                _find_column(
                    table.headers,
                    item,
                    table=f"{path.name}/{table.sheet_name}",
                )
            matching_tables.append(table)
        except InputContractError:
            continue
    if not matching_tables:
        raise InputContractError(f"无法在 {path} 中定位调度中心/服务区节点表")
    nodes: dict[str, Node] = {}
    for table in matching_tables:
        cols = [
            _find_column(
                table.headers,
                item,
                table=f"{path.name}/{table.sheet_name}",
            )
            for item in aliases
        ]
        for row_no, row in _data_rows(table):
            node_id = _canonical_node_id(row[cols[0]])
            if not node_id:
                continue
            # The workbook contains a title row for the second table and a
            # separate per-aircraft table below the 16 task nodes.  Those
            # rows are not part of the node contract.
            if node_id != "O01" and not node_id.startswith("S"):
                continue
            lon = _number(row[cols[1]], field="经度", row=row_no)
            lat = _number(row[cols[2]], field="纬度", row=row_no)
            if not -180 <= lon <= 180 or not -90 <= lat <= 90:
                raise InputContractError(f"节点 {node_id} 的经纬度超出范围")
            if node_id in nodes:
                previous = nodes[node_id]
                if (
                    not math.isclose(previous.longitude_deg, lon, rel_tol=0, abs_tol=1e-12)
                    or not math.isclose(previous.latitude_deg, lat, rel_tol=0, abs_tol=1e-12)
                ):
                    raise InputContractError(f"节点编号重复且坐标冲突: {node_id}")
                continue
            nodes[node_id] = Node(node_id, lon, lat)
    if len(nodes) != 16 or "O01" not in nodes:
        raise InputContractError(
            f"节点合同不满足：需要 O01+15 个服务区，实际 {len(nodes)} 个节点"
        )
    if len([key for key in nodes if key.startswith("S")]) != 15:
        raise InputContractError("节点合同不满足：服务区数量不是 15")
    return nodes


def _load_boxes(path: Path) -> tuple[CargoBox, ...]:
    aliases = [
        ("货箱编号", "箱体编号", "箱号", "货物编号", "box_id", "id"),
        ("服务区编号", "服务区", "配送服务区", "area_id", "service_area"),
        ("质量", "重量", "货箱质量", "mass", "mass_kg"),
        ("体积", "货箱体积", "volume", "volume_m3"),
    ]
    table = _choose_table(path, [item[0:] for item in aliases])
    cols = [
        _find_column(table.headers, item, table=f"{path.name}/{table.sheet_name}")
        for item in aliases
    ]
    deadline_col = _find_optional_column(
        table.headers, ("配送时限", "期望送达时间", "时限", "deadline", "deadline_s")
    )
    boxes: list[CargoBox] = []
    seen: set[str] = set()
    for row_no, row in _data_rows(table):
        box_id = _text(row[cols[0]])
        if not box_id:
            continue
        if box_id in seen:
            raise InputContractError(f"货箱编号重复: {box_id}")
        area = _canonical_area_id(row[cols[1]])
        mass = _number(row[cols[2]], field="货箱质量", row=row_no)
        volume = _number(row[cols[3]], field="货箱体积", row=row_no)
        if mass <= 0 or volume <= 0:
            raise InputContractError(f"货箱 {box_id} 的质量和体积必须为正")
        deadline = (
            _number(row[deadline_col], field="配送时限", row=row_no)
            if deadline_col is not None and row[deadline_col] is not None
            else None
        )
        boxes.append(CargoBox(box_id, area, mass, volume, deadline))
        seen.add(box_id)
    if len(boxes) != 80:
        raise InputContractError(
            f"货箱合同不满足：题目规定 80 个不可拆货箱，实际读取 {len(boxes)} 个"
        )
    return tuple(boxes)


def _load_uav_types(path: Path) -> dict[str, UAVType]:
    aliases = [
        ("机型编号", "运输机型", "无人机型号", "型号", "机型", "type_id", "type"),
        ("含电池空载总质量", "空载总质量", "空载质量", "empty_mass"),
        ("最大载货质量", "最大载荷", "额定载荷", "最大货载", "Q_g", "payload"),
        ("可用装载体积", "装载体积", "货舱体积", "最大装载体积", "V_g", "volume_capacity"),
        ("空载标准航程", "空载航程", "空载续航", "L_g^0", "L0", "range_empty"),
        ("满载标准航程", "满载航程", "满载续航", "L_g^F", "LF", "range_full"),
        ("计划巡航速度", "巡航速度", "水平速度", "v_g^c", "cruise_speed", "vc"),
        ("最大爬升速度", "爬升速度", "上升速度", "v_g^up", "climb_speed", "vup"),
        ("最大下降速度", "下降速度", "下滑速度", "v_g^down", "descent_speed", "vdown"),
        ("可用能量", "可用电量", "单组电池可用能量", "E_g^use", "usable_energy"),
        (
            "返航安全余量",
            "返航电量下限",
            "安全余量比例",
            "余量比例",
            "rho_g",
            "reserve_ratio",
        ),
        ("爬升能耗效率", "爬升效率", "climb_efficiency"),
        ("下降能耗效率", "下降效率", "descent_efficiency"),
        ("工位固定准备时间", "固定准备时间", "准备时间", "preparation_time_s"),
        ("每箱装载时间", "装载时间", "loading_time_per_box_s"),
        ("接收点基础交接时间", "基础交接时间", "卸货基础时间", "handoff_base_time_s"),
        ("每箱增加交接时间", "每箱交接时间", "卸货每箱时间", "handoff_time_per_box_s"),
    ]
    table = _choose_table(path, [item[0:] for item in aliases])
    cols = [
        _find_column(table.headers, item, table=f"{path.name}/{table.sheet_name}")
        for item in aliases
    ]
    uavs: dict[str, UAVType] = {}
    for row_no, row in _data_rows(table):
        if len(uavs) == 3:
            # The same worksheet continues with a separate per-aircraft
            # inventory table after the three type rows.
            break
        type_id = _text(row[cols[0]]).upper()
        if not type_id:
            continue
        if type_id in uavs:
            raise InputContractError(f"运输机型编号重复: {type_id}")
        empty_mass = _number(row[cols[1]], field=aliases[1][0], row=row_no)
        max_payload = _number(row[cols[2]], field=aliases[2][0], row=row_no)
        volume = _number(row[cols[3]], field=aliases[3][0], row=row_no)
        empty_range = _number(row[cols[4]], field=aliases[4][0], row=row_no)
        full_range = _number(row[cols[5]], field=aliases[5][0], row=row_no)
        cruise = _number(row[cols[6]], field=aliases[6][0], row=row_no)
        climb = _number(row[cols[7]], field=aliases[7][0], row=row_no)
        descent = _number(row[cols[8]], field=aliases[8][0], row=row_no)
        energy = _number(row[cols[9]], field=aliases[9][0], row=row_no)
        reserve = _fraction(
            row[cols[10]],
            table.headers[cols[10]],
            field=aliases[10][0],
            row=row_no,
        )
        climb_efficiency = _fraction(
            row[cols[11]],
            table.headers[cols[11]],
            field=aliases[11][0],
            row=row_no,
        )
        descent_efficiency = _fraction(
            row[cols[12]],
            table.headers[cols[12]],
            field=aliases[12][0],
            row=row_no,
        )
        preparation_time = _number(
            row[cols[13]], field=aliases[13][0], row=row_no
        )
        loading_time_per_box = _number(
            row[cols[14]], field=aliases[14][0], row=row_no
        )
        handoff_base_time = _number(
            row[cols[15]], field=aliases[15][0], row=row_no
        )
        handoff_time_per_box = _number(
            row[cols[16]], field=aliases[16][0], row=row_no
        )
        if min(
            empty_mass,
            max_payload,
            volume,
            empty_range,
            full_range,
            climb,
            cruise,
            descent,
            energy,
            climb_efficiency,
        ) <= 0:
            raise InputContractError(f"运输机型 {type_id} 存在非正参数")
        if full_range > empty_range:
            raise InputContractError(
                f"运输机型 {type_id} 的满载航程大于空载航程，无法使用题目公式"
            )
        if min(
            preparation_time,
            loading_time_per_box,
            handoff_base_time,
            handoff_time_per_box,
        ) < 0:
            raise InputContractError(f"运输机型 {type_id} 的作业时间参数不能为负")
        uavs[type_id] = UAVType(
            type_id=type_id,
            max_payload_kg=max_payload,
            empty_range_m=empty_range,
            full_range_m=full_range,
            climb_speed_mps=climb,
            cruise_speed_mps=cruise,
            descent_speed_mps=descent,
            usable_energy_kwh=energy,
            reserve_ratio=reserve,
            volume_capacity_m3=volume,
            empty_mass_kg=empty_mass,
            climb_efficiency=climb_efficiency,
            descent_efficiency=descent_efficiency,
            preparation_time_s=preparation_time,
            loading_time_per_box_s=loading_time_per_box,
            handoff_base_time_s=handoff_base_time,
            handoff_time_per_box_s=handoff_time_per_box,
        )
    if len(uavs) != 3:
        raise InputContractError(
            f"运输机型合同不满足：题目规定 3 种运输机型，实际读取 {len(uavs)} 种"
        )
    return uavs


def load_inputs(data_dir: str | Path) -> InputBundle:
    """读取问题一所需的输入，并拒绝不完整或有歧义的附件。"""

    root = Path(data_dir).resolve()
    if not root.is_dir():
        raise MissingInputError(f"数据目录不存在: {root}")
    node_file = _locate(root, "调度中心与服务区.xlsx")
    box_file = _locate(root, "物资需求与配送时限.xlsx")
    uav_file = _locate(root, "运输无人机数据.xlsx")
    dem_file = _locate_dem(root)
    nodes = _load_nodes(node_file)
    boxes = _load_boxes(box_file)
    uav_types = _load_uav_types(uav_file)
    areas = {box.service_area_id for box in boxes}
    node_areas = {node_id for node_id in nodes if node_id.startswith("S")}
    if areas != node_areas:
        raise InputContractError(
            f"箱体服务区集合与节点集合不一致：箱体={sorted(areas)}，节点={sorted(node_areas)}"
        )
    geo_descriptions = [
        path
        for path in root.rglob("*")
        if path.is_file()
        and path.suffix.lower() == ".pdf"
        and "地理空间数据说明" in path.stem
    ]
    extra_sources = [geo_descriptions[0]] if len(geo_descriptions) == 1 else []
    return InputBundle(
        nodes=nodes,
        boxes=boxes,
        uav_types=uav_types,
        source_files=tuple(
            str(path)
            for path in (node_file, box_file, uav_file, dem_file, *extra_sources)
        ),
        dem_path=str(dem_file),
    )
