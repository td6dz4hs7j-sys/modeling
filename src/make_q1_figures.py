"""Generate the Q1 raw/process/result figures from real run outputs.

This script intentionally contains no synthetic observations.  It reads the
validated input bundle and the CSV/JSON files produced by src.run_q1.
"""

from __future__ import annotations

import csv
import json
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.patches import FancyBboxPatch, Polygon, Rectangle

from .data_loader import load_inputs
from .energy_model import load_energy_provider, round_trip_energy_kwh
from .terrain import DEM, build_routes


ROOT = Path(__file__).resolve().parents[1]
FIGURES = ROOT / "figures"
RESULTS = ROOT / "results"
TYPE_ORDER = ["A", "B", "C"]
TYPE_COLORS = {"A": "#0072B2", "B": "#E69F00", "C": "#009E73"}


def _style() -> None:
    plt.rcParams.update(
        {
            "figure.dpi": 120,
            "savefig.dpi": 300,
            "font.size": 9,
            "axes.titlesize": 10,
            "axes.labelsize": 9,
            "xtick.labelsize": 8,
            "ytick.labelsize": 8,
            "legend.fontsize": 8,
            "axes.spines.top": False,
            "axes.spines.right": False,
            "axes.unicode_minus": False,
            "pdf.fonttype": 42,
            "ps.fonttype": 42,
            "svg.fonttype": "none",
        }
    )


def _save_pair(fig: plt.Figure, stem: str) -> None:
    FIGURES.mkdir(parents=True, exist_ok=True)
    fig.savefig(FIGURES / f"{stem}.png", dpi=300)
    fig.savefig(FIGURES / f"{stem}.svg")
    plt.close(fig)


def _read_csv(name: str) -> list[dict[str, str]]:
    with (RESULTS / name).open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def _load() -> tuple[object, dict, dict, list[dict], list[dict], dict]:
    inputs = load_inputs(ROOT / "data")
    provider = load_energy_provider("src.problem_energy_provider", inputs.uav_types)
    with DEM.open(inputs.dem_path) as dem:
        routes = build_routes(inputs.nodes, dem)
    payload_rows = _read_csv("q1_安全载荷.csv")
    method_rows = _read_csv("q1_方法比较.csv")
    selected_rows = _read_csv("q1_组批方案.csv")
    sensitivity = json.loads((RESULTS / "q1_余量敏感性.json").read_text(encoding="utf-8"))
    return inputs, routes, provider, payload_rows, method_rows, selected_rows, sensitivity


def make_raw_figures(inputs: object) -> None:
    boxes = list(inputs.boxes)
    masses = np.array([box.mass_kg for box in boxes])
    volumes = np.array([box.volume_m3 for box in boxes])
    areas = sorted({box.service_area_id for box in boxes})
    area_index = {area: i + 1 for i, area in enumerate(areas)}

    fig, ax = plt.subplots(figsize=(6.2, 4.0))
    bins = np.arange(0, masses.max() + 2, 2)
    ax.hist(masses, bins=bins, color="#56B4E9", edgecolor="white")
    ax.set(
        xlabel="Box mass (kg)",
        ylabel="Number of boxes",
        title="Raw Q1: individual box mass distribution",
    )
    ax.text(
        0.98,
        0.95,
        f"n = {len(boxes)}\nmedian = {np.median(masses):.1f} kg",
        transform=ax.transAxes,
        ha="right",
        va="top",
    )
    _save_pair(fig, "raw_q1_box_mass_distribution")

    fig, ax = plt.subplots(figsize=(6.2, 4.0))
    scatter = ax.scatter(
        masses,
        volumes,
        c=[area_index[box.service_area_id] for box in boxes],
        cmap="cividis",
        s=28,
        alpha=0.85,
        edgecolors="white",
        linewidths=0.3,
    )
    cbar = fig.colorbar(scatter, ax=ax)
    cbar.set_label("Service-area index")
    ax.set(
        xlabel="Box mass (kg)",
        ylabel="Box volume (m³)",
        title="Raw Q1: mass-volume relationship",
    )
    _save_pair(fig, "raw_q1_box_mass_volume")

    area_mass = {
        area: sum(box.mass_kg for box in boxes if box.service_area_id == area)
        for area in areas
    }
    area_count = {
        area: sum(box.service_area_id == area for box in boxes)
        for area in areas
    }
    ordered = sorted(areas, key=lambda area: area_mass[area])
    fig, ax = plt.subplots(figsize=(6.6, 4.4))
    bars = ax.barh(
        ordered,
        [area_mass[area] for area in ordered],
        color="#009E73",
        alpha=0.85,
    )
    ax.set(xlabel="Total requested mass (kg)", ylabel="Service area", title="Raw Q1: demand mass by service area")
    for bar, area in zip(bars, ordered):
        ax.text(
            bar.get_width() + 2,
            bar.get_y() + bar.get_height() / 2,
            f"{area_count[area]} boxes",
            va="center",
            fontsize=7,
        )
    ax.set_xlim(0, max(area_mass.values()) * 1.18)
    _save_pair(fig, "raw_q1_area_demand_mass")


def make_process_figures(
    inputs: object,
    routes: dict,
    provider: object,
    payload_rows: list[dict[str, str]],
    selected_rows: list[dict[str, str]],
) -> None:
    areas = sorted(routes)
    index = np.arange(len(areas))
    distances_km = np.array([routes[area].outbound.distance_m / 1000 for area in areas])
    max_ground = np.array(
        [routes[area].outbound.max_ground_elevation_m for area in areas]
    )
    fig, ax = plt.subplots(figsize=(6.6, 4.4))
    points = ax.scatter(
        distances_km,
        max_ground,
        c=index + 1,
        cmap="cividis",
        s=45,
        edgecolors="white",
        linewidths=0.4,
    )
    for x, y, area in zip(distances_km, max_ground, areas):
        ax.annotate(area, (x, y), xytext=(3, 3), textcoords="offset points", fontsize=7)
    cbar = fig.colorbar(points, ax=ax)
    cbar.set_label("Service-area index")
    ax.set(
        xlabel="One-way distance (km)",
        ylabel="Maximum ground elevation (m)",
        title="Process Q1: route geometry from the DEM",
    )
    _save_pair(fig, "process_q1_dem_route_profile")

    selected_areas = [area for area in ["S001", "S008", "S014"] if area in routes]
    fig, axes = plt.subplots(1, len(selected_areas), figsize=(10.0, 3.3), sharey=True)
    if len(selected_areas) == 1:
        axes = [axes]
    for ax, area in zip(axes, selected_areas):
        route = routes[area]
        for type_id in TYPE_ORDER:
            uav = inputs.uav_types[type_id]
            qs = np.linspace(0, uav.max_payload_kg, 100)
            energies = [
                round_trip_energy_kwh(provider, uav, route, float(q))
                for q in qs
            ]
            ax.plot(
                qs,
                energies,
                color=TYPE_COLORS[type_id],
                label=f"Type {type_id}",
                linewidth=1.7,
            )
            allowed = (1 - uav.reserve_ratio) * uav.usable_energy_kwh
            ax.axhline(allowed, color=TYPE_COLORS[type_id], alpha=0.2, linewidth=0.8)
        ax.set_title(area)
        ax.set_xlabel("Outbound payload (kg)")
        ax.grid(axis="y", alpha=0.22)
    axes[0].set_ylabel("Round-trip energy (kWh)")
    axes[-1].legend(frameon=False, loc="upper left")
    fig.suptitle("Process Q1: payload-energy curves under reference model A", y=0.98)
    fig.tight_layout(rect=(0, 0, 1, 0.90))
    _save_pair(fig, "process_q1_payload_energy_curves")

    soc = np.array([float(row["返航SOC_%"]) for row in selected_rows])
    order = np.argsort(soc)
    fig, ax = plt.subplots(figsize=(6.6, 4.0))
    ax.scatter(
        np.arange(1, len(soc) + 1),
        soc[order],
        color="#0072B2",
        s=35,
        zorder=3,
    )
    ax.axhline(20, color="#D55E00", linestyle="--", linewidth=1.2, label="20% reserve floor")
    ax.set(
        xlabel="Selected-solution batch rank (sorted by return SOC)",
        ylabel="Return SOC (%)",
        title="Process Q1: selected-batch reserve slack",
    )
    ax.legend(frameon=False)
    ax.set_ylim(0, 100)
    _save_pair(fig, "process_q1_selected_soc_slack")


def make_result_figures(
    payload_rows: list[dict[str, str]],
    method_rows: list[dict[str, str]],
    sensitivity: dict,
) -> None:
    method_names = [row["方法"] for row in method_rows]
    labels = ["FFD baseline", "FFD + local", "MILP", "MILP + local"]
    colors = ["#999999", "#56B4E9", "#E69F00", "#009E73"]
    metrics = [
        ("架次数", "Sorties", "sorties"),
        ("总运输能耗_kWh", "Energy (kWh)", "energy_kwh"),
        ("累计作业时间_s", "Cumulative flight time (s)", "time_s"),
    ]
    fig, axes = plt.subplots(1, 3, figsize=(10.2, 3.8))
    for ax, (column, xlabel, _) in zip(axes, metrics):
        values = [float(row[column]) for row in method_rows]
        y = np.arange(len(values))
        ax.barh(y, values, color=colors[: len(values)])
        ax.set_yticks(y, labels[: len(values)])
        ax.invert_yaxis()
        ax.set_xlabel(xlabel)
        ax.grid(axis="x", alpha=0.2)
        for yi, value in zip(y, values):
            ax.text(value, yi, f"  {value:.2f}" if value < 1000 else f"  {value:.0f}", va="center", fontsize=7)
    fig.suptitle("Result Q1: baseline and improvement comparison", y=0.98)
    fig.tight_layout(rect=(0, 0, 1, 0.90))
    _save_pair(fig, "result_q1_method_comparison")

    areas = sorted({row["服务区编号"] for row in payload_rows})
    matrix = np.array(
        [
            [
                float(
                    next(
                        row["最大安全载荷_kg"]
                        for row in payload_rows
                        if row["机型编号"] == type_id
                        and row["服务区编号"] == area
                    )
                )
                for area in areas
            ]
            for type_id in TYPE_ORDER
        ]
    )
    fig, ax = plt.subplots(figsize=(8.4, 2.8))
    image = ax.imshow(matrix, aspect="auto", cmap="viridis")
    ax.set_xticks(np.arange(len(areas)), areas, rotation=45, ha="right")
    ax.set_yticks(np.arange(len(TYPE_ORDER)), [f"Type {type_id}" for type_id in TYPE_ORDER])
    ax.set_xlabel("Service area")
    ax.set_ylabel("Transport UAV type")
    ax.set_title("Result Q1: maximum safe payload (kg)")
    for i in range(matrix.shape[0]):
        for j in range(matrix.shape[1]):
            ax.text(j, i, f"{matrix[i, j]:.1f}", ha="center", va="center", fontsize=6, color="white" if matrix[i, j] < 65 else "black")
    cbar = fig.colorbar(image, ax=ax)
    cbar.set_label("Safe payload (kg)")
    fig.tight_layout()
    _save_pair(fig, "result_q1_safe_payload_heatmap")

    records = sensitivity["records"]
    rho = np.array([record["rho"] for record in records])
    fig, axes = plt.subplots(2, 1, figsize=(6.6, 6.0), sharex=True)
    axes[0].plot(
        rho,
        [record["ffd"]["sorties"] for record in records],
        marker="o",
        color="#999999",
        label="FFD",
    )
    axes[0].plot(
        rho,
        [record["local_search"]["sorties"] for record in records],
        marker="s",
        color="#0072B2",
        label="FFD + local search",
    )
    axes[0].set_ylabel("Sorties")
    axes[0].set_title("Result Q1: reserve-ratio sensitivity")
    axes[0].legend(frameon=False)
    axes[0].grid(alpha=0.2)
    for type_id in TYPE_ORDER:
        minimum = [
            min(
                value
                for key, value in record["safe_payloads_kg"].items()
                if key.startswith(f"{type_id}/")
            )
            for record in records
        ]
        axes[1].plot(
            rho,
            minimum,
            marker="o",
            color=TYPE_COLORS[type_id],
            label=f"Type {type_id}",
        )
    axes[1].set(xlabel="Reserve ratio rho", ylabel="Minimum safe payload (kg)")
    axes[1].legend(frameon=False, ncol=3)
    axes[1].grid(alpha=0.2)
    fig.tight_layout()
    _save_pair(fig, "result_q1_reserve_sensitivity")


def _node(ax: plt.Axes, xy: tuple[float, float], text: str, *, kind: str) -> None:
    x, y = xy
    if kind == "start":
        patch = FancyBboxPatch(
            (x - 0.9, y - 0.3),
            1.8,
            0.6,
            boxstyle="round,pad=0.03,rounding_size=0.08",
            facecolor="#E6E6E6",
            edgecolor="#333333",
        )
    elif kind == "data":
        patch = Polygon(
            [(x - 0.85, y - 0.3), (x + 0.85, y - 0.3), (x + 0.65, y + 0.3), (x - 1.05, y + 0.3)],
            closed=True,
            facecolor="#F0F0F0",
            edgecolor="#333333",
        )
    elif kind == "decision":
        patch = Polygon(
            [(x, y + 0.42), (x + 1.0, y), (x, y - 0.42), (x - 1.0, y)],
            closed=True,
            facecolor="#FFF2CC",
            edgecolor="#333333",
        )
    else:
        patch = Rectangle(
            (x - 0.9, y - 0.3),
            1.8,
            0.6,
            facecolor="#EAF2F8",
            edgecolor="#333333",
        )
    ax.add_patch(patch)
    ax.text(x, y, text, ha="center", va="center", fontsize=8)


def _arrow(ax: plt.Axes, start: tuple[float, float], end: tuple[float, float]) -> None:
    ax.annotate(
        "",
        xy=end,
        xytext=start,
        arrowprops={"arrowstyle": "->", "color": "#333333", "lw": 1.1},
    )


def make_flow_figures() -> None:
    fig, ax = plt.subplots(figsize=(12, 2.8))
    ax.set_xlim(-1.2, 14.0)
    ax.set_ylim(-1, 1)
    ax.axis("off")
    nodes = [
        (0, "Inputs", "start"),
        (2.1, "XLSX + DEM", "data"),
        (4.2, "Q1 physical\nmodel", "process"),
        (6.3, "FFD baseline", "process"),
        (8.4, "All constraints\npass?", "decision"),
        (10.5, "Local search /\nMILP compare", "process"),
        (12.5, "CSV + JSON\nresults", "start"),
    ]
    for x, label, kind in nodes:
        _node(ax, (x, 0), label, kind=kind)
    for left, right in zip(nodes, nodes[1:]):
        _arrow(ax, (left[0] + 0.95, 0), (right[0] - 0.95, 0))
    ax.text(8.4, -0.7, "If no: stop and record BLOCKED", ha="center", fontsize=8)
    _save_pair(fig, "flow_overall_model")

    fig, ax = plt.subplots(figsize=(8.4, 5.0))
    ax.set_xlim(-1, 7)
    ax.set_ylim(-1.3, 5.2)
    ax.axis("off")
    vertical = [
        ((3, 4.7), "1. Read and\nvalidate inputs", "data"),
        ((3, 3.6), "2. Build DEM\nroutes", "process"),
        ((3, 2.5), "3. Compute safe\npayloads", "process"),
        ((3, 1.4), "4. FFD then\nvalidate", "process"),
        ((3, 0.3), "5. Compare local\nsearch / MILP", "process"),
    ]
    for (x, y), label, kind in vertical:
        _node(ax, (x, y), label, kind=kind)
    for current, nxt in zip(vertical, vertical[1:]):
        _arrow(ax, (3, current[0][1] - 0.35), (3, nxt[0][1] + 0.35))
    _node(ax, (5.5, 1.4), "Constraint\nchecks", kind="decision")
    _arrow(ax, (3.95, 1.4), (4.5, 1.4))
    _arrow(ax, (5.5, 1.0), (3.85, 0.55))
    _node(ax, (3, -0.8), "Selected Q1\nsolution", kind="start")
    _arrow(ax, (3, -0.05), (3, -0.45))
    _save_pair(fig, "flow_q1_model")


def main() -> None:
    _style()
    inputs, routes, provider, payload_rows, method_rows, selected_rows, sensitivity = _load()
    make_raw_figures(inputs)
    make_process_figures(inputs, routes, provider, payload_rows, selected_rows)
    make_result_figures(payload_rows, method_rows, sensitivity)
    make_flow_figures()
    print(f"generated figures in {FIGURES}")


if __name__ == "__main__":
    main()
