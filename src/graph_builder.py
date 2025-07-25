import networkx as nx
import plotly.graph_objects as go
import pandas as pd
import numpy as np
import time
from typing import Dict, List, Tuple, Set, Optional, Any
from dataclasses import dataclass


@dataclass
class NodeStyle:
    """Data class for node styling properties."""

    glow: bool = False
    opacity: float = 1.0
    border: str = "#000000"
    original_border: str = "#000000"


@dataclass
class LayoutConfig:
    """Configuration for graph layout parameters."""

    x_spacing: float = 3.4  # Increased from 3.0 for even more breathing room
    local_y_spacing: float = 0.7
    tier_vertical_gap: float = 0.6
    min_box_width: float = 0.6
    max_box_width: float = 1.4
    corner_radius: float = 0.06
    max_line_length: int = 18
    sigmoid_steepness: float = 6.0


class GraphBuilder:
    """
    Builds a fixed-layout DAG using NetworkX and Plotly.
    Nodes are rectangles organized by tier (X axis) and maturity (Y axis).
    Edges are curved S-lines with arrowheads and weight-scaled color intensity.
    Glow effects are now handled by client-side JavaScript for modern UX.
    """

    # Class constants
    TIER_BAND_COLORS = {1.0: "#fde2e2", 1.5: "#ffeeba", 2.0: "#fff9c4"}
    X_GROUP_LABELS = {
        1: "Foundational Domains",
        2: "Tier 1 Dependency Domains",
        3: "Tier 2 Dependency Domains",
        4: "Resulting Domains",
    }
    TIER_LABEL_MAP = {
        1: "Optimizer",
        2: "Optimizer",
        3: "Partial Blocker",
        4: "Blocker",
    }
    BRIGHTNESS_MAP = {2: +0.3, 3: 0.0, 4: -0.3}

    def __init__(
        self,
        nodes_df: pd.DataFrame,
        edges_df: pd.DataFrame,
        sigmoid_steepness: float = 6.0,
    ):
        """Initialize GraphBuilder with dataframes and configuration."""
        self.nodes_df = nodes_df.copy()
        self.edges_df = edges_df.copy()
        self.config = LayoutConfig(sigmoid_steepness=sigmoid_steepness)
        self.sigmoid_steepness = sigmoid_steepness  # Keep for backward compatibility

        # Set individual attributes for backward compatibility
        self.x_spacing = self.config.x_spacing
        self.local_y_spacing = self.config.local_y_spacing
        self.tier_vertical_gap = self.config.tier_vertical_gap
        self.box_width = 0.8  # Dynamic default, will be overridden per node
        self.corner_radius = self.config.corner_radius
        self.max_line_length = self.config.max_line_length

        # Keep original attributes for backward compatibility
        self.tier_band_colors = self.TIER_BAND_COLORS
        self.x_group_labels = self.X_GROUP_LABELS

        # Pre-calculate node dimensions for consistent layout
        self.node_dimensions = self._precalculate_node_dimensions()

    def _wrap_label_intelligently(self, text: str) -> Tuple[str, int]:
        """Intelligently wrap text with adaptive line length for optimal readability."""
        if not text:
            return "", 1

        words = text.split()
        if not words:
            return "", 1

        # Adaptive target based on text length for better line breaks
        total_chars = len(text)
        if total_chars <= 15:
            target_chars = total_chars  # Keep short text on one line
        elif total_chars <= 30:
            target_chars = 16  # Medium text, good for 2 lines
        else:
            target_chars = 18  # Longer text, allow wider lines

        lines = []
        current_line = ""

        for word in words:
            test_line = current_line + (" " if current_line else "") + word

            if len(test_line) <= target_chars:
                current_line = test_line
            else:
                if current_line:
                    lines.append(current_line)
                    current_line = word
                else:
                    # Handle very long words intelligently
                    if len(word) > target_chars:
                        # Try to break at natural points first
                        if "-" in word:
                            parts = word.split("-", 1)
                            if len(parts[0]) <= target_chars - 1:
                                lines.append(parts[0] + "-")
                                current_line = parts[1]
                            else:
                                # Force break with hyphen
                                lines.append(word[: target_chars - 1] + "-")
                                current_line = word[target_chars - 1 :]
                        else:
                            # Force break with hyphen as last resort
                            lines.append(word[: target_chars - 1] + "-")
                            current_line = word[target_chars - 1 :]
                    else:
                        current_line = word

        if current_line:
            lines.append(current_line)

        if not lines:
            lines = [""]

        return "<br>".join(lines), len(lines)

    def _calculate_optimal_column_widths(self) -> Dict[int, float]:
        """Calculate optimal width for each X-group based on longest domain name."""
        column_widths = {}

        for x_group in self.nodes_df["X_GROUP"].unique():
            column_nodes = self.nodes_df[self.nodes_df["X_GROUP"] == x_group]

            # Find the longest domain name in this column
            longest_name = ""
            for _, row in column_nodes.iterrows():
                if len(row["DOMAIN_NAME"]) > len(longest_name):
                    longest_name = row["DOMAIN_NAME"]

            # Calculate optimal width for the longest name
            if longest_name:
                # Wrap the longest text to see how it flows
                wrapped_text, line_count = self._wrap_label_intelligently(longest_name)

                # Calculate width based on the longest line
                lines = wrapped_text.split("<br>")
                max_line_length = max(len(line) for line in lines) if lines else 0

                # Character width estimation + generous padding
                char_width = 0.07  # Slightly wider chars for better spacing
                padding = 0.25  # Generous padding on both sides

                optimal_width = max(0.8, max_line_length * char_width + padding)

                # Cap maximum width for visual balance
                optimal_width = min(optimal_width, 1.6)

                column_widths[x_group] = optimal_width
            else:
                column_widths[x_group] = 0.9  # Default fallback

        return column_widths

    def _precalculate_node_dimensions(self) -> Dict[str, Tuple[float, float]]:
        """Pre-calculate column-adaptive dimensions for all nodes."""
        dimensions = {}

        # Calculate optimal width for each column
        column_widths = self._calculate_optimal_column_widths()

        for _, row in self.nodes_df.iterrows():
            label = row["DOMAIN_NAME"]
            x_group = row["X_GROUP"]

            # Use the column's optimal width
            node_width = column_widths[x_group]

            # Smart wrapping optimized for this column's width
            wrapped_label, line_count = self._wrap_label_intelligently(label)

            # Calculate height based on line count with good proportions
            base_height = 0.18  # Good base padding
            line_height = 0.12  # Comfortable line spacing
            total_height = base_height + (line_count * line_height)

            dimensions[row["DOMAIN_ID"]] = (node_width, total_height, wrapped_label)

        return dimensions

    def _rounded_rect_path(
        self, x0: float, y0: float, x1: float, y1: float, r: float
    ) -> str:
        """Generate SVG path for rounded rectangle."""
        return (
            f"M{x0+r},{y0} H{x1-r} Q{x1},{y0} {x1},{y0+r} "
            f"V{y1-r} Q{x1},{y1} {x1-r},{y1} H{x0+r} Q{x0},{y1} {x0},{y1-r} "
            f"V{y0+r} Q{x0},{y0} {x0+r},{y0} Z"
        )

    def _adjust_brightness(self, hex_color: str, shift: float) -> str:
        """Adjust brightness of a hex color by blending toward white (+) or black (−)."""
        hex_color = hex_color.lstrip("#")
        rgb = [int(hex_color[i : i + 2], 16) for i in (0, 2, 4)]

        if shift > 0:
            blend = lambda c: int(c + (255 - c) * shift)
        else:
            blend = lambda c: int(c * (1 + shift))

        adjusted = tuple(blend(c) for c in rgb)
        return f"rgb({adjusted[0]},{adjusted[1]},{adjusted[2]})"

    def _calculate_tier_offsets(self) -> Dict[float, float]:
        """Calculate Y-axis offsets for each tier."""
        sorted_tiers = sorted(self.TIER_BAND_COLORS)
        return {
            tier: idx * self.config.tier_vertical_gap * 6
            for idx, tier in enumerate(sorted_tiers)
        }

    def _assign_stacked_positions(self) -> Dict[str, Tuple[float, float]]:
        """Assign X,Y positions to nodes with intelligent collision avoidance."""
        positions = {}
        used_y_coords = {}  # Track y-coord and height pairs
        tier_offsets = self._calculate_tier_offsets()

        for tier in sorted(self.TIER_BAND_COLORS):
            tier_df = self.nodes_df[np.isclose(self.nodes_df["CURRENT_MATURITY"], tier)]

            for x_group, group in tier_df.groupby("X_GROUP"):
                sorted_group = group.sort_values("DOMAIN_NAME")
                count = len(sorted_group)
                y_spacing = self.config.local_y_spacing

                # Get heights for this group
                group_heights = [
                    self.node_dimensions[row["DOMAIN_ID"]][1]
                    for _, row in sorted_group.iterrows()
                ]

                # Find non-colliding positions with height awareness
                for _ in range(15):
                    y_grid = self._calculate_y_grid(count, y_spacing)
                    y_positions = [tier_offsets[tier] + offset for offset in y_grid]

                    if not self._has_intelligent_collisions(
                        y_positions, group_heights, used_y_coords, x_group
                    ):
                        break
                    y_spacing *= 1.08

                # Assign positions and track them
                for offset, height, (_, row) in zip(
                    y_grid, group_heights, sorted_group.iterrows()
                ):
                    x = x_group * self.config.x_spacing
                    y = tier_offsets[tier] + offset
                    positions[row["DOMAIN_ID"]] = (x, y)
                    used_y_coords[(x_group, y)] = height

        return positions

    def _calculate_y_grid(self, count: int, y_spacing: float) -> np.ndarray:
        """Calculate Y-grid positions for a group of nodes."""
        if count == 1:
            return np.array([0])
        y_grid = np.linspace(0, (count - 1) * y_spacing, count)
        return y_grid - np.mean(y_grid)

    def _has_intelligent_collisions(
        self,
        y_positions: List[float],
        heights: List[float],
        used_coords: Dict[Tuple[int, float], float],
        current_x_group: int,
    ) -> bool:
        """Check for collisions considering node heights and visual spacing."""
        min_gap = 0.15  # Minimum visual gap between nodes

        for i, (y, height) in enumerate(zip(y_positions, heights)):
            node_top = y + height / 2
            node_bottom = y - height / 2

            # Check against existing nodes in the same x-group
            for (x_group, existing_y), existing_height in used_coords.items():
                if x_group == current_x_group:
                    existing_top = existing_y + existing_height / 2
                    existing_bottom = existing_y - existing_height / 2

                    # Check for overlap with buffer
                    if not (
                        node_bottom > existing_top + min_gap
                        or node_top < existing_bottom - min_gap
                    ):
                        return True

        return False

    def _build_networkx_graph(
        self, positions: Dict[str, Tuple[float, float]]
    ) -> nx.DiGraph:
        """Build NetworkX graph with nodes and edges."""
        G = nx.DiGraph()

        # Add nodes with pre-calculated dimensions
        for _, row in self.nodes_df.iterrows():
            width, height, wrapped_label = self.node_dimensions[row["DOMAIN_ID"]]
            G.add_node(
                row["DOMAIN_ID"],
                label=row["DOMAIN_NAME"],
                wrapped_label=wrapped_label,
                category=row["CATEGORY"],
                color=row["COLOR_HEX"],
                border=row["BORDER_HEX"],
                original_border=row["BORDER_HEX"],
                pos=positions[row["DOMAIN_ID"]],
                width=width,
                height=height,
            )

        # Add edges
        for _, row in self.edges_df.iterrows():
            G.add_edge(
                row["SOURCE_DOMAIN_ID"],
                row["TARGET_DOMAIN_ID"],
                weight=row["WEIGHT"],
                tier=row["TIER"],
                description=row["DESCRIPTION"],
            )

        return G

    def _generate_true_s_curve(
        self,
        x0: float,
        y0: float,
        x1: float,
        y1: float,
        resolution: int = 50,
        steepness: float = 15.0,
    ) -> Tuple[np.ndarray, np.ndarray]:
        """Generate smooth S-curve between two points."""
        t = np.linspace(0, 1, resolution)
        s = 1 / (1 + np.exp(-steepness * (t - 0.5)))
        dx = x1 - x0
        dy = y1 - y0
        curve_x = x0 + dx * t
        curve_y = y0 + dy * s
        return curve_x, curve_y

    def _generate_flat_side_arc(
        self,
        x0: float,
        y0: float,
        x1: float,
        y1: float,
        direction: str = "right",
        offset: float = 0.6,
        resolution: int = 50,
    ) -> Tuple[np.ndarray, np.ndarray]:
        """Generate flatter cubic Bezier arc for same-x dependencies."""
        t = np.linspace(0, 1, resolution)
        arc_shift = offset if direction == "right" else -offset

        # Cubic Bezier control points
        ctrl1_x = x0 + arc_shift
        ctrl1_y = y0
        ctrl2_x = x1 + arc_shift
        ctrl2_y = y1

        arc_x = (
            (1 - t) ** 3 * x0
            + 3 * (1 - t) ** 2 * t * ctrl1_x
            + 3 * (1 - t) * t**2 * ctrl2_x
            + t**3 * x1
        )
        arc_y = (
            (1 - t) ** 3 * y0
            + 3 * (1 - t) ** 2 * t * ctrl1_y
            + 3 * (1 - t) * t**2 * ctrl2_y
            + t**3 * y1
        )

        return arc_x, arc_y

    def _determine_interaction_state(
        self,
        G: nx.DiGraph,
        selected: Optional[str],
        hovered: Optional[str],
        mode: str,
    ) -> Tuple[Set[str], Set[str], Set[str]]:
        """Determine which nodes to highlight, dim, or show as secondary."""

        if hovered == "RESET":
            hovered = None

        highlight_nodes = set()
        secondary_nodes = set()
        dim_nodes = set()

        if mode == "filter" and (selected is None or selected == "All"):
            return set(), set(), set()

        if selected and selected in G.nodes:
            highlight_nodes.add(selected)
            secondary_nodes.update([v for u, v in G.out_edges(selected)])
            secondary_nodes.update([u for u, v in G.in_edges(selected)])

        if hovered and hovered != selected and hovered in G.nodes:
            highlight_nodes.add(hovered)

        # Here's the key line:
        if mode == "filter":
            dim_nodes = set(G.nodes) - highlight_nodes - secondary_nodes
        elif mode == "interactive" and selected:
            dim_nodes = set(G.nodes) - highlight_nodes - secondary_nodes
        else:
            dim_nodes = set()  # Don't dim anything if no selection in interactive

        return highlight_nodes, secondary_nodes, dim_nodes

    def _apply_node_styles(
        self,
        G: nx.DiGraph,
        selected: Optional[str],
        hovered: Optional[str],
        highlight_nodes: Set[str],
        dim_nodes: Set[str],
    ) -> None:
        """Apply visual styles to nodes based on interaction state."""
        # Handle hover reset
        if hovered == "RESET":
            hovered = None

        for node in G.nodes():
            style = NodeStyle(
                glow=False,  # Keep for JavaScript layer reference
                opacity=1.0,
                border=G.nodes[node]["original_border"],
                original_border=G.nodes[node]["original_border"],
            )

            # Selected node gets black border (highest priority)
            if node == selected:
                style.border = "#000000"
                style.opacity = 1.0

            # Hovered node gets glow flag (for JS layer) and border change
            if node == hovered:
                style.glow = True  # This will be used by JavaScript DOM layer
                if node != selected:
                    style.border = "#FFD700"

            # Dim nodes that aren't involved
            if dim_nodes and node in dim_nodes:
                style.opacity = 0.2

            # Apply styles to node (glow flag kept for JS layer)
            G.nodes[node]["glow"] = style.glow
            G.nodes[node]["opacity"] = style.opacity
            G.nodes[node]["border"] = style.border

    def _determine_visible_elements(
        self,
        G: nx.DiGraph,
        selected: Optional[str],
        hovered: Optional[str],
        directions: List[str],
        mode: str,
    ) -> Tuple[Set[str], List[Tuple[str, str, Dict]]]:
        """Determine which nodes and edges should be visible."""
        # Handle hover reset
        if hovered == "RESET":
            hovered = None

        all_nodes = set(G.nodes())
        visible_nodes = set()
        visible_edges = []

        if selected == "All":
            selected = None

        if mode == "filter":
            if selected and selected in all_nodes:
                visible_nodes.add(selected)
                visible_edges.extend(
                    self._get_directional_edges(G, selected, directions)
                )
                # Add connected nodes to visible set
                for u, v, _ in visible_edges:
                    visible_nodes.add(u)
                    visible_nodes.add(v)
            else:
                visible_nodes = all_nodes
                visible_edges = list(G.edges(data=True))

        elif mode == "interactive":
            if selected and selected in all_nodes:
                # SELECTED NODE: Filter to show only selected node and its connections
                visible_nodes.add(selected)
                visible_edges.extend(
                    self._get_directional_edges(G, selected, directions)
                )
                # Add connected nodes to visible set
                for u, v, _ in visible_edges:
                    visible_nodes.add(u)
                    visible_nodes.add(v)

            else:
                # NO SELECTION: Show all nodes (allows clicking, but hover will highlight)
                visible_nodes = all_nodes
                visible_edges = list(G.edges(data=True))

        return visible_nodes, visible_edges

    def _get_directional_edges(
        self, G: nx.DiGraph, node: str, directions: List[str]
    ) -> List[Tuple[str, str, Dict]]:
        """Get edges in specified directions from a node."""
        edges = []
        if "upstream" in directions:
            for u, v in G.in_edges(node):
                edges.append((u, v, G[u][v]))
        if "downstream" in directions:
            for u, v in G.out_edges(node):
                edges.append((u, v, G[u][v]))
        return edges

    def _get_edge_color(self, xu: int, xv: int, tier: int) -> str:
        """Determine edge color based on tier pair and apply brightness adjustment."""
        tier_pair = {xu, xv}

        if tier_pair == {1, 2}:
            base_color = "#4A90E2"
        elif tier_pair in [{1, 3}, {2, 3}]:
            base_color = "#72CBE2"
        elif tier_pair & {1, 2, 3} and 4 in tier_pair:
            base_color = "#A680B8"
        else:
            base_color = "#4A90E2"

        brightness_shift = self.BRIGHTNESS_MAP.get(tier, 0.0)
        return self._adjust_brightness(base_color, brightness_shift)

    def _create_edge_traces(
        self,
        G: nx.DiGraph,
        pos: Dict[str, Tuple[float, float]],
        visible_edges: List[Tuple[str, str, Dict]],
        visible_nodes: Set[str],
        mode: str,
    ) -> Tuple[List[go.Scatter], List[Dict]]:
        """Create edge traces with clean custom arrow shapes."""
        edge_traces = []
        arrow_shapes = []

        for u, v, data in visible_edges:
            x0, y0 = pos[u]
            x1, y1 = pos[v]
            xu = int(
                self.nodes_df[self.nodes_df["DOMAIN_ID"] == u]["X_GROUP"].values[0]
            )
            xv = int(
                self.nodes_df[self.nodes_df["DOMAIN_ID"] == v]["X_GROUP"].values[0]
            )

            # Get node widths for proper edge positioning
            source_width = G.nodes[u]["width"]
            target_width = G.nodes[v]["width"]

            edge_color = self._get_edge_color(xu, xv, data["tier"])

            # Generate edge curve
            if xu == xv:
                direction = "right" if u == G.nodes[v].get("pos_id", v) else "left"
                edge_x, edge_y = self._generate_same_x_edge(
                    x0, y0, x1, y1, direction, source_width
                )
            else:
                edge_x, edge_y = self._generate_different_x_edge(
                    x0, y0, x1, y1, xu, xv, source_width, target_width
                )

            edge_opacity = 0.6

            # Create edge trace (lines only)
            tier_label = self.TIER_LABEL_MAP.get(
                int(data["tier"]), f"Tier {data['tier']}"
            )
            edge_traces.append(
                go.Scatter(
                    x=edge_x,
                    y=edge_y,
                    mode="lines",
                    line=dict(width=3 * data["weight"], color=edge_color),
                    opacity=edge_opacity,
                    hoverinfo="text",
                    text=f"<b>{G.nodes[u]['label']}  ➔  {G.nodes[v]['label']}</b><br>{data['description']}<br>Dependency Type: <b>{tier_label}</b>",
                    showlegend=False,
                )
            )

            # Create clean custom arrow shape
            arrow_shapes.append(
                self._create_clean_arrow_shape(edge_x, edge_y, edge_color, edge_opacity)
            )

        return edge_traces, arrow_shapes

    def _create_clean_arrow_shape(
        self,
        edge_x: np.ndarray,
        edge_y: np.ndarray,
        edge_color: str,
        edge_opacity: float,
    ) -> Dict:
        """Create a clean, well-proportioned arrow shape that follows the curve properly."""
        if len(edge_x) < 2:
            return {}

        # Get the actual curve direction at the end
        tip_x, tip_y = edge_x[-1], edge_y[-1]

        # Use multiple points for better direction calculation
        num_points = min(5, len(edge_x))
        base_x = np.mean(edge_x[-num_points:-1])
        base_y = np.mean(edge_y[-num_points:-1])

        # Calculate direction vector
        dx = tip_x - base_x
        dy = tip_y - base_y
        length = (dx**2 + dy**2) ** 0.5

        if length > 0:
            # Normalize direction
            dx /= length
            dy /= length

            # Perpendicular vector for arrow wings
            px, py = -dy, dx

            # Arrow dimensions
            arrow_length = 0.08
            arrow_width = 0.04

            # Calculate arrow points
            base_point_x = tip_x - dx * arrow_length
            base_point_y = tip_y - dy * arrow_length

            wing1_x = base_point_x + px * arrow_width
            wing1_y = base_point_y + py * arrow_width

            wing2_x = base_point_x - px * arrow_width
            wing2_y = base_point_y - py * arrow_width

            # Create a clean triangular arrow
            return dict(
                type="path",
                path=f"M {wing1_x},{wing1_y} L {tip_x},{tip_y} L {wing2_x},{wing2_y} Z",
                fillcolor=edge_color,
                line=dict(color=edge_color, width=1),
                layer="above",
                opacity=edge_opacity,
            )

        return {}

    def _generate_same_x_edge(
        self,
        x0: float,
        y0: float,
        x1: float,
        y1: float,
        direction: str,
        node_width: float,
    ) -> Tuple[np.ndarray, np.ndarray]:
        """Generate edge curve for same X-group nodes."""
        if direction == "right":
            x0 += node_width / 2
            x1 += node_width / 2
        else:
            x0 -= node_width / 2
            x1 -= node_width / 2

        return self._generate_flat_side_arc(x0, y0, x1, y1, direction=direction)

    def _generate_different_x_edge(
        self,
        x0: float,
        y0: float,
        x1: float,
        y1: float,
        xu: int,
        xv: int,
        source_width: float,
        target_width: float,
    ) -> Tuple[np.ndarray, np.ndarray]:
        """Generate edge curve for different X-group nodes."""
        if xu < xv:
            x0 += source_width / 2
            x1 -= target_width / 2
        elif xu > xv:
            x0 -= source_width / 2
            x1 += target_width / 2

        return self._generate_true_s_curve(x0, y0, x1, y1)

    def _create_tier_backgrounds(
        self, G: nx.DiGraph, pos: Dict[str, Tuple[float, float]]
    ) -> Tuple[List[Dict], List[Dict]]:
        """Create tier background shapes and annotations with flexible X-axis expansion."""
        tier_bg_shapes = []
        tier_annotations = []

        # Calculate dynamic X-range based on nodes and potential edge extensions
        node_x_coords = [x for x, y in pos.values()]
        node_widths = [G.nodes[node]["width"] for node in G.nodes()]

        # Account for node widths and edge curves that extend beyond nodes
        max_node_width = max(node_widths) if node_widths else 0.8
        edge_extension = 1.2  # Extra space for curved edges (especially side arcs)

        x_min = min(node_x_coords) - max_node_width / 2 - edge_extension
        x_max = max(node_x_coords) + max_node_width / 2 + edge_extension

        tier_y_extents = self._calculate_tier_extents(G, pos)
        tier_tops, tier_bottoms = self._calculate_tier_boundaries(tier_y_extents)

        for tier in [1.0, 1.5, 2.0]:
            if tier not in tier_y_extents:
                continue

            color = self.TIER_BAND_COLORS.get(tier, "#ffffff")
            y0, y1 = self._calculate_tier_band_bounds(tier, tier_tops, tier_bottoms)

            tier_bg_shapes.append(
                dict(
                    type="rect",
                    xref="x",
                    yref="y",
                    x0=x_min,
                    x1=x_max,
                    y0=y0,
                    y1=y1,
                    fillcolor=color,
                    opacity=0.3,
                    layer="below",
                    line_width=0,
                )
            )

            tier_center = (y0 + y1) / 2
            tier_annotations.append(
                dict(
                    x=x_min
                    - 0.3,  # Position tier labels closer to the expanded background
                    y=tier_center,
                    text=f"<b>Tier {tier}</b>",
                    showarrow=False,
                    font=dict(size=18, color="black", family="Inter, sans-serif"),
                    xanchor="right",
                    yanchor="middle",
                    opacity=1.0,
                )
            )

        return tier_bg_shapes, tier_annotations

    def _calculate_tier_extents(
        self, G: nx.DiGraph, pos: Dict[str, Tuple[float, float]]
    ) -> Dict[float, List[Tuple[float, float]]]:
        """Calculate Y extents for each tier."""
        tier_y_extents = {}

        for n in G.nodes():
            y = pos[n][1]
            height = G.nodes[n]["height"]
            tier = float(
                self.nodes_df[self.nodes_df["DOMAIN_ID"] == n][
                    "CURRENT_MATURITY"
                ].values[0]
            )
            top = y + height / 2
            bottom = y - height / 2
            tier_y_extents.setdefault(tier, []).append((top, bottom))

        return tier_y_extents

    def _calculate_tier_boundaries(
        self, tier_y_extents: Dict[float, List[Tuple[float, float]]]
    ) -> Tuple[Dict[float, float], Dict[float, float]]:
        """Calculate top and bottom boundaries for each tier."""
        tier_tops = {
            tier: max(t for t, _ in bounds) + 0.5 * np.mean([t - b for t, b in bounds])
            for tier, bounds in tier_y_extents.items()
        }
        tier_bottoms = {
            tier: min(b for _, b in bounds) - 0.5 * np.mean([t - b for t, b in bounds])
            for tier, bounds in tier_y_extents.items()
        }
        return tier_tops, tier_bottoms

    def _calculate_tier_band_bounds(
        self,
        tier: float,
        tier_tops: Dict[float, float],
        tier_bottoms: Dict[float, float],
    ) -> Tuple[float, float]:
        """Calculate Y bounds for a tier band."""
        if tier == 1.0 and 1.5 in tier_tops and tier in tier_bottoms:
            top = tier_bottoms[tier]
            bottom = (tier_tops[tier] + tier_bottoms[1.5]) / 2
        elif tier == 1.5 and 1.0 in tier_tops and 2.0 in tier_bottoms:
            top = (tier_tops[1.0] + tier_bottoms[1.5]) / 2
            bottom = (tier_tops[1.5] + tier_bottoms[2.0]) / 2
        elif tier == 2.0 and 1.5 in tier_tops and tier in tier_tops:
            top = (tier_tops[1.5] + tier_bottoms[2.0]) / 2
            bottom = tier_tops[tier]
        else:
            top = tier_bottoms[tier]
            bottom = tier_tops[tier]

        return min(top, bottom), max(top, bottom)

    def _create_node_shapes_and_annotations(
        self,
        G: nx.DiGraph,
        pos: Dict[str, Tuple[float, float]],
        visible_nodes: Set[str],
    ) -> Tuple[List[Dict], List[Dict]]:
        """Create node shapes and text annotations with proper dimensions.
        
        Note: Glow effects are now handled by client-side JavaScript DOM manipulation
        for better performance and modern UX polish.
        """
        shapes = []
        annotations = []

        for n in G.nodes():
            x, y = pos[n]
            width = G.nodes[n]["width"]
            height = G.nodes[n]["height"]
            x0, x1 = x - width / 2, x + width / 2
            y0, y1 = y - height / 2, y + height / 2

            # REMOVED: Glow effect creation - now handled by JavaScript DOM layer
            # Glow flag is still tracked in node data for JavaScript reference

            # Add main node shape
            shapes.append(
                dict(
                    type="path",
                    path=self._rounded_rect_path(
                        x0, y0, x1, y1, self.config.corner_radius
                    ),
                    fillcolor=G.nodes[n]["color"],
                    line=dict(color=G.nodes[n].get("border", "#000000"), width=4),
                    layer="above",
                    opacity=G.nodes[n].get("opacity", 1.0),
                )
            )

            # Add text annotation
            annotations.append(
                dict(
                    x=x,
                    y=y,
                    text=G.nodes[n]["wrapped_label"],
                    font=dict(size=11, color="black", family="Inter, sans-serif"),
                    showarrow=False,
                    yanchor="middle",
                    opacity=G.nodes[n].get("opacity", 1.0),
                )
            )

        return shapes, annotations

    def _create_x_group_annotations(
        self,
        G: nx.DiGraph,
        pos: Dict[str, Tuple[float, float]],
        tier_tops: Dict[float, float],
    ) -> List[Dict]:
        """Create X-axis group label annotations."""
        annotations = []
        x_group_positions = {x: [] for x in self.X_GROUP_LABELS}

        for node_id, (x, y) in pos.items():
            x_group = int(
                self.nodes_df[self.nodes_df["DOMAIN_ID"] == node_id]["X_GROUP"].values[
                    0
                ]
            )
            x_group_positions[x_group].append((x, y))

        x_label_y = tier_tops.get(2.0, max(y for _, y in pos.values())) + 0.6

        for x_group, positions_xy in x_group_positions.items():
            if not positions_xy:
                continue

            xs = [x for x, _ in positions_xy]
            x_center = np.mean(xs)

            annotations.append(
                dict(
                    x=x_center,
                    y=x_label_y,
                    text=f"<b>{self.X_GROUP_LABELS.get(x_group, f'Group {x_group}')}</b>",
                    showarrow=False,
                    font=dict(size=18, color="black", family="Inter, sans-serif"),
                    xanchor="center",
                    yanchor="bottom",
                    opacity=1.0,
                )
            )

        return annotations

    def _create_interactive_node_trace(
        self, G: nx.DiGraph, pos: Dict[str, Tuple[float, float]]
    ) -> go.Scatter:
        """Create transparent scatter trace for node interactivity."""
        node_x, node_y, node_labels, node_ids = [], [], [], []

        for node_id in G.nodes():
            x, y = pos[node_id]
            node_x.append(x)
            node_y.append(y)
            node_labels.append(G.nodes[node_id]["label"])
            node_ids.append(node_id)

        return go.Scatter(
            x=node_x,
            y=node_y,
            mode="markers",
            text=node_labels,
            customdata=node_ids,
            hoverinfo="text",
            marker=dict(
                symbol="square",
                sizemode="diameter",
                sizeref=1,
                size=[max(w, h) * 100 for w, h, _ in self.node_dimensions.values()],
                color="rgba(0,0,0,0)",
                opacity=0.1,
            ),
            showlegend=False,
        )

    def _calculate_figure_height(self, pos: Dict[str, Tuple[float, float]]) -> int:
        """Calculate appropriate figure height based on node positions."""
        y_range = max(y for _, y in pos.values()) - min(y for _, y in pos.values())
        return max(900, int((y_range + 2) * 150))

    def _calculate_plot_bounds(
        self, pos: Dict[str, Tuple[float, float]], G: nx.DiGraph
    ) -> Tuple[float, float, float, float]:
        """Calculate optimal plot bounds considering nodes, edges, and UI elements."""
        node_x_coords = [x for x, y in pos.values()]
        node_y_coords = [y for x, y in pos.values()]

        # Get node dimensions for proper boundary calculation
        node_widths = [G.nodes[node]["width"] for node in G.nodes()]
        node_heights = [G.nodes[node]["height"] for node in G.nodes()]

        max_node_width = max(node_widths) if node_widths else 0.8
        max_node_height = max(node_heights) if node_heights else 0.3

        # Calculate base ranges
        base_x_min = min(node_x_coords) - max_node_width / 2
        base_x_max = max(node_x_coords) + max_node_width / 2
        base_y_min = min(node_y_coords) - max_node_height / 2
        base_y_max = max(node_y_coords) + max_node_height / 2

        # Add generous padding for edges and UI elements (increased for wider spacing)
        edge_padding = 2.2  # Increased significantly for generous edge curves
        ui_padding_x = 1.2  # Increased for much wider layout
        ui_padding_y_bottom = 0.8  # Space below for any bottom elements
        ui_padding_y_top = 1.5  # Extra space above for X-group headers

        x_min = base_x_min - edge_padding - ui_padding_x
        x_max = base_x_max + edge_padding
        y_min = base_y_min - ui_padding_y_bottom
        y_max = base_y_max + ui_padding_y_top

        return x_min, x_max, y_min, y_max

    def build_figure(
        self,
        selected: Optional[str] = None,
        directions: List[str] = ["upstream", "downstream"],
        mode: str = "filter",
        hovered: Optional[str] = None,
    ) -> go.Figure:
        """
        Build the complete Plotly figure with all components.
        
        Glow effects are now handled by client-side JavaScript for modern UX.

        Args:
            selected: ID of selected node
            directions: List of direction filters ("upstream", "downstream")
            mode: Interaction mode ("filter" or "interactive")
            hovered: ID of hovered node

        Returns:
            Plotly Figure object
        """
        # Step 1: Calculate positions and build graph
        positions = self._assign_stacked_positions()
        G = self._build_networkx_graph(positions)
        pos = nx.get_node_attributes(G, "pos")

        # Step 2: Determine interaction state
        highlight_nodes, secondary_nodes, dim_nodes = self._determine_interaction_state(
            G, selected, hovered, mode
        )

        # Step 3: Apply node styles
        self._apply_node_styles(G, selected, hovered, highlight_nodes, dim_nodes)

        # Step 4: Determine visible elements
        visible_nodes, visible_edges = self._determine_visible_elements(
            G, selected, hovered, directions, mode
        )

        # Step 5: Create edge traces with properly oriented arrows (LIMIT TO VISIBLE ONLY)
        edge_traces, arrow_shapes = (
            self._create_edge_traces(G, pos, visible_edges, visible_nodes, mode)
            if visible_edges
            else ([], [])
        )

        # Step 6: Create tier backgrounds
        tier_bg_shapes, tier_annotations = self._create_tier_backgrounds(G, pos)

        # Step 7: Create node shapes and annotations (glow now handled by JS)
        node_shapes, node_annotations = self._create_node_shapes_and_annotations(
            G, pos, visible_nodes
        )

        # Step 8: Create X-group annotations
        tier_y_extents = self._calculate_tier_extents(G, pos)
        tier_tops, _ = self._calculate_tier_boundaries(tier_y_extents)
        x_group_annotations = self._create_x_group_annotations(G, pos, tier_tops)

        # Step 9: Create interactive node trace
        interactive_trace = self._create_interactive_node_trace(G, pos)

        # Step 10: Calculate layout bounds
        x_min, x_max, y_min, y_max = self._calculate_plot_bounds(pos, G)

        # Enforce wide layout if needed
        min_x_range = 16.5
        x_range = x_max - x_min
        if x_range < min_x_range:
            center_x = (x_min + x_max) / 2
            x_min = center_x - min_x_range / 2
            x_max = center_x + min_x_range / 2

        # Step 11: Final figure assembly with FORCED refresh trigger
        fig = go.Figure(data=edge_traces + [interactive_trace])

        # ADD REVISION TO FORCE RERENDER
        # Every time we build the figure, increment revision to force Plotly refresh
        revision_trigger = int(time.time() * 1000)  # Millisecond timestamp

        fig.update_layout(
            clickmode="event+select",  # Ensure click events emit
            dragmode=False,  # Optional: disable pan/zoom
            datarevision=revision_trigger,  # FORCE PLOTLY TO REFRESH
            height=self._calculate_figure_height(pos),
            margin=dict(l=50, r=30, t=50, b=30),
            plot_bgcolor="white",
            hovermode="closest",
            xaxis=dict(
                showgrid=False,
                zeroline=False,
                showticklabels=False,
                range=[x_min, x_max],
                constrain="domain",
            ),
            yaxis=dict(
                showgrid=False,
                zeroline=False,
                showticklabels=False,
                range=[y_min, y_max],
                constrain="domain",
            ),
            shapes=tier_bg_shapes + node_shapes + arrow_shapes,
            annotations=tier_annotations + node_annotations + x_group_annotations,
        )

        return fig