"""问题一唯一正式入口。

运行顺序：读入合同 -> DEM/路线 -> 安全载荷 -> FFD 基线验证 ->
局部搜索/MILP 对照 -> 结果与敏感性输出。
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import platform
import sys
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .data_loader import load_inputs
from .energy_model import load_energy_provider, round_trip_time_s
from .exceptions import Q1Error
from .optimization import solve_q1
from .sensitivity import detect_switch_points, scan_reserve_ratio
from .terrain import DEM, build_routes


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )


def _write_status(
    output_dir: Path,
    *,
    status: str,
    message: str,
    data_dir: Path,
    missing_or_next: list[str] | None = None,
) -> None:
    _write_json(
        output_dir / "运行状态.json",
        {
            "status": status,
            "message": message,
            "data_dir": str(data_dir),
            "missing_or_next": missing_or_next or [],
            "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            "python": sys.version,
            "platform": platform.platform(),
        },
    )


def _solution_objective(solution: Any) -> tuple[float, float, float, str]:
    return (
        solution.total_sorties,
        solution.total_energy_kwh,
        solution.total_time_s,
        solution.method,
    )


def _select_solution(run: Any) -> Any:
    candidates = [run.baseline, run.local_search]
    if run.milp is not None:
        candidates.append(run.milp)
    if run.milp_local_search is not None:
        candidates.append(run.milp_local_search)
    return min(candidates, key=_solution_objective)


def _write_solution_csv(output_dir: Path, run: Any) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    with (output_dir / "q1_安全载荷.csv").open(
        "w", newline="", encoding="utf-8-sig"
    ) as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "机型编号",
                "服务区编号",
                "最大安全载荷_kg",
                "往返能耗_kWh",
                "允许任务能量_kWh",
                "往返距离_m",
                "安全载荷对应航程_m",
                "零载荷是否可行",
                "搜索方法",
            ]
        )
        for item in run.payload_results:
            writer.writerow(
                [
                    item.uav_type_id,
                    item.service_area_id,
                    item.safe_payload_kg,
                    item.round_trip_energy_kwh,
                    item.allowed_energy_kwh,
                    item.round_trip_distance_m,
                    item.range_at_safe_payload_m,
                    item.feasible_at_zero_payload,
                    item.search_method,
                ]
            )

    solutions = [
        ("FFD baseline", run.baseline),
        ("local search", run.local_search),
    ]
    if run.milp is not None:
        solutions.append(("MILP minimum-sortie", run.milp))
    if run.milp_local_search is not None:
        solutions.append(("MILP + local search", run.milp_local_search))
    with (output_dir / "q1_方法比较.csv").open(
        "w", newline="", encoding="utf-8-sig"
    ) as handle:
        writer = csv.writer(handle)
        writer.writerow(
            ["方法", "架次数", "总运输能耗_kWh", "累计作业时间_s", "搜索是否完整"]
        )
        for name, solution in solutions:
            writer.writerow(
                [
                    name,
                    solution.total_sorties,
                    solution.total_energy_kwh,
                    solution.total_time_s,
                    solution.complete_search,
                ]
            )

    selected = _select_solution(run)
    with (output_dir / "q1_组批方案.csv").open(
        "w", newline="", encoding="utf-8-sig"
    ) as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "架次编号",
                "服务区编号",
                "机型编号",
                "货箱编号列表",
                "总质量_kg",
                "总体积_m3",
                "往返时间_s",
                "架次能耗_kWh",
                "返航SOC_%",
            ]
        )
        for batch in selected.batches:
            writer.writerow(
                [
                    batch.batch_id,
                    batch.service_area_id,
                    batch.uav_type_id,
                    ";".join(batch.box_ids),
                    batch.mass_kg,
                    batch.volume_m3,
                    batch.flight_time_s,
                    batch.energy_kwh,
                    batch.return_soc_ratio * 100.0,
                ]
            )

    validations = dict(run.validations)
    validations["selected_solution"] = validate_solution_for_selected(run, selected)
    _write_json(output_dir / "q1_约束验证.json", validations)


def _write_route_geometry(output_dir: Path, routes: dict, uav_types: dict) -> None:
    with (output_dir / "q1_路线几何.csv").open(
        "w", newline="", encoding="utf-8-sig"
    ) as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "服务区编号",
                "单程距离_m",
                "最高地面高程_m",
                "巡航海拔_m",
                "去程爬升_m",
                "去程下降_m",
                "返程爬升_m",
                "返程下降_m",
                *[
                    f"{type_id}_往返飞行时间_s"
                    for type_id in sorted(uav_types)
                ],
            ]
        )
        for area_id in sorted(routes):
            route = routes[area_id]
            writer.writerow(
                [
                    area_id,
                    route.outbound.distance_m,
                    route.outbound.max_ground_elevation_m,
                    route.outbound.cruise_altitude_m,
                    route.outbound.climb_m,
                    route.outbound.descent_m,
                    route.inbound.climb_m,
                    route.inbound.descent_m,
                    *[
                        round_trip_time_s(uav_types[type_id], route)
                        for type_id in sorted(uav_types)
                    ],
                ]
            )


def validate_solution_for_selected(run: Any, selected: Any) -> dict:
    """Return the already recorded validation for the selected candidate."""

    for key in ("ffd_baseline", "local_search", "milp", "milp_local_search"):
        candidate = getattr(run, key, None)
        if candidate is selected:
            return {
                "selected_method": selected.method,
                "reference_validation": run.validations[key],
            }
    return {
        "selected_method": selected.method,
        "reference_validation": None,
        "warning": "selected solution is not present in the validation map",
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="D题问题一求解")
    parser.add_argument("--data-dir", default="data", help="题目数据目录")
    parser.add_argument("--output-dir", default="results", help="结果目录")
    parser.add_argument(
        "--energy-provider",
        default="",
        help="显式能耗适配器模块；需提供 build_provider(uav_types)",
    )
    parser.add_argument("--seed", type=int, default=0, help="记录用的确定性种子")
    parser.add_argument(
        "--no-milp",
        action="store_true",
        help="只运行 FFD + 局部搜索，不运行 MILP 对照",
    )
    parser.add_argument(
        "--milp-time-limit-s",
        type=float,
        default=120.0,
        help="每个 MILP 对照的时间上限",
    )
    parser.add_argument(
        "--reserve-values",
        type=float,
        nargs="*",
        default=None,
        help="敏感性扫描的 rho 值；不提供则不猜测扫描区间",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    data_dir = Path(args.data_dir).resolve()
    output_dir = Path(args.output_dir).resolve()
    try:
        inputs = load_inputs(data_dir)
        provider = load_energy_provider(args.energy_provider, inputs.uav_types)
        with DEM.open(inputs.dem_path) as dem:
            routes = build_routes(inputs.nodes, dem)
        run = solve_q1(
            inputs.boxes,
            inputs.uav_types,
            routes,
            provider,
            try_milp=not args.no_milp,
            milp_time_limit_s=args.milp_time_limit_s,
        )
        _write_solution_csv(output_dir, run)
        _write_route_geometry(output_dir, routes, inputs.uav_types)
        if args.reserve_values:
            sensitivity = scan_reserve_ratio(
                inputs.boxes,
                inputs.uav_types,
                routes,
                provider,
                args.reserve_values,
                try_milp=False,
            )
            _write_json(
                output_dir / "q1_余量敏感性.json",
                {
                    "records": sensitivity,
                    "switch_points": detect_switch_points(sensitivity),
                },
            )
        _write_json(
            output_dir / "运行状态.json",
            {
                "status": "COMPLETE",
                "message": "问题一真实数据链已运行并通过当前代码验证",
                "method": "FFD -> local search; optional MILP comparison",
                "selected_method": _select_solution(run).method,
                "selected_metrics": {
                    "sorties": _select_solution(run).total_sorties,
                    "energy_kwh": _select_solution(run).total_energy_kwh,
                    "time_s": _select_solution(run).total_time_s,
                },
                "provider_source": provider.source,
                "seed": args.seed,
                "input_files": [
                    {"path": path, "sha256": _sha256(Path(path))}
                    for path in inputs.source_files
                ],
                "notes": list(run.notes),
            },
        )
        print("Q1 complete")
        return 0
    except Q1Error as exc:
        _write_status(
            output_dir,
            status="BLOCKED",
            message=str(exc),
            data_dir=data_dir,
            missing_or_next=[
                "补齐题目原始 XLSX、30 米 DEM 和说明文件",
                "核验并实现 E_hor/E_up 能耗适配器后通过 --energy-provider 注入",
                "重新运行唯一复现命令并完成 M1/P1",
            ],
        )
        print(f"Q1 BLOCKED: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
