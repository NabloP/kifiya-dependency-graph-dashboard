from dash import html, dcc
import pandas as pd
from .graph_builder import GraphBuilder
from typing import Dict, List, Any
import json


class LayoutBuilder:
    """
    Constructs the full Dash layout for the DAG visualization app.

    This refactored version moves all CSS and JavaScript to external files
    for better maintainability and separation of concerns.

    CLEAN INTERACTIONS SYSTEM:
    ✨ Hover: Subtle border + light fill
    🎯 Selection: Stronger border + optional pulse
    ⚡ Fast: 0.15s transitions
    🎨 Professional: Notion/Linear inspired design
    """

    def __init__(self, nodes_path: str, edges_path: str):
        """Initialize LayoutBuilder with data paths and configuration."""
        # Load and process data
        self.nodes_df = pd.read_csv(nodes_path)
        self.edges_df = pd.read_csv(edges_path, encoding="ISO-8859-1")

        # Apply tier encoding
        self._apply_tier_mapping()

        # Initialize graph builder
        self.graph_builder = GraphBuilder(self.nodes_df, self.edges_df)

        # Configuration for clean interactions
        self.config = {
            "sidebar_width": "250px",
            "graph_height": "1600px",
            "responsive_breakpoint": "768px",
        }

    def _apply_tier_mapping(self) -> None:
        """Apply tier encoding to nodes dataframe."""
        tier_map = {
            "Foundational": 1,
            "Tier 1 Dependency": 2,
            "Tier 2 Dependency": 3,
            "Compilatory": 4,
        }
        self.nodes_df["X_GROUP"] = self.nodes_df["TIER_GROUP"].map(tier_map)
        self.nodes_df["Y_RANK"] = self.nodes_df["CURRENT_MATURITY"]

    def create_layout(self, app) -> html.Div:
        """
        Create the complete Dash layout.

        Note: CSS and JS are now loaded from the assets folder automatically by Dash.
        """
        # Inject node dimensions data into the page
        app.index_string = self._generate_index_string()

        return html.Div(
            children=[
                self._build_header(),
                self._build_collapse_button(),
                self._build_main_area(),
                self._build_state_stores(),
            ],
            style={"height": "100vh", "display": "flex", "flexDirection": "column"},
        )

    def _generate_index_string(self) -> str:
        """Generate minimal index string with just the node dimensions data."""
        node_dimensions_json = json.dumps(self.get_node_dimensions_for_js())

        return f"""
        <!DOCTYPE html>
        <html>
        <head>
            {{%metas%}}
            <title>{{%title%}}</title>
            {{%favicon%}}
            {{%css%}}
            <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600&display=swap" rel="stylesheet">
            <script>
                // Node dimensions data - injected at runtime
                window.nodeDimensions = {node_dimensions_json};
            </script>
        </head>
        <body>
            {{%app_entry%}}
            <footer>
                {{%config%}}
                {{%scripts%}}
                {{%renderer%}}
            </footer>
        </body>
        </html>
        """

    def _build_header(self) -> html.H2:
        """Build the application header."""
        return html.H2(
            "📊 Kifiya Data & AI Maturity Dependency Graph",
            style={
                "textAlign": "center",
                "marginTop": "12px",
                "color": "#333",
                "fontWeight": "600",
                "marginBottom": "16px",
            },
        )

    def _build_collapse_button(self) -> html.Button:
        """Build the sidebar collapse button."""
        return html.Button(
            "⇤",
            id="collapse-button",
            n_clicks=0,
            className="collapse-button",
            style={
                "position": "absolute",
                "top": "12px",
                "left": "12px",
                "zIndex": 1000,
                "fontSize": "18px",
                "padding": "6px 10px",
                "border": "1px solid #ccc",
                "borderRadius": "6px",
                "backgroundColor": "#fff",
                "cursor": "pointer",
                "fontWeight": "600",
                "color": "#666",
            },
        )

    def _build_main_area(self) -> html.Div:
        """Build the main application area containing sidebar and graph."""
        return html.Div(
            children=[
                self._build_sidebar(),
                self._build_graph_area(),
            ],
            style={
                "display": "flex",
                "flexDirection": "row",
                "width": "100%",
                "height": "100%",
                "flex": 1,
            },
        )

    def _build_sidebar(self) -> html.Div:
        """Build the sidebar with controls and status indicators."""
        domain_options = [{"label": "All Domains", "value": "All"}] + [
            {"label": row["DOMAIN_NAME"], "value": row["DOMAIN_ID"]}
            for _, row in self.nodes_df.iterrows()
        ]

        return html.Div(
            id="sidebar-container",
            children=[
                self._build_mode_controls(),
                self._build_direction_controls(),
                self._build_domain_selector(domain_options),
                #self._build_glow_toggle(),
                self._build_reset_controls(),
                #self._build_status_indicator(),
            ],
            style={
                "width": self.config["sidebar_width"],
                "padding": "12px 16px",
                "borderRight": "1px solid #e0e0e0",
                "backgroundColor": "#fafafa",
                "flexShrink": 0,
                "borderTopRightRadius": "8px",
            },
        )

    def _build_mode_controls(self) -> html.Div:
        """Build mode control elements."""
        return html.Div(
            [
                html.Label(
                    "View Mode:",
                    className="sidebar-label",
                ),
                dcc.RadioItems(
                    id="mode-toggle",
                    options=[
                        {"label": " Filter", "value": "filter"},
                        {"label": " Interactive", "value": "interactive"},
                    ],
                    value="interactive",
                    inline=True,
                    className="radio-control",
                ),
            ],
            className="control-group",
        )

    def _build_direction_controls(self) -> html.Div:
        """Build direction control elements."""
        return html.Div(
            [
                html.Label(
                    "Flow Direction:",
                    className="sidebar-label",
                ),
                dcc.Checklist(
                    id="direction-toggle",
                    options=[
                        {"label": " Upstream", "value": "upstream"},
                        {"label": " Downstream", "value": "downstream"},
                    ],
                    value=["upstream", "downstream"],
                    inline=True,
                    className="checkbox-control",
                ),
            ],
            className="control-group",
        )

    def _build_domain_selector(self, domain_options: List[Dict[str, str]]) -> html.Div:
        """Build domain selector dropdown."""
        return html.Div(
            id="dropdown-wrapper",
            children=[
                html.Label(
                    "Select Domain:",
                    className="sidebar-label",
                ),
                dcc.Dropdown(
                    id="domain-selector",
                    options=domain_options,
                    placeholder="e.g. DSP.6",
                    className="domain-dropdown",
                ),
            ],
            className="control-group",
        )

    def _build_glow_toggle(self) -> html.Div:
        """Build glow effect toggle control."""
        return html.Div(
            [
                html.Label("Glow Effects:", className="sidebar-label"),
                dcc.Checklist(
                    id="glow-toggle",
                    options=[{"label": " Enable Hover Glow", "value": "enabled"}],
                    value=[],  # Default OFF
                    inline=True,
                    className="checkbox-control",
                ),
            ],
            className="control-group",
        )

    def _build_reset_controls(self) -> html.Div:
        """Build reset control elements."""
        return html.Div(
            id="reset-wrapper",
            children=[
                html.Label(
                    "Selection Control:",
                    className="sidebar-label",
                ),
                html.Button(
                    "Reset View",
                    id="reset-button",
                    n_clicks=0,
                    className="reset-button",
                ),
            ],
            className="control-group",
            style={"display": "none"},
        )

    def _build_status_indicator(self) -> html.Div:
        """Build interaction status indicator."""
        return html.Div(
            id="interaction-status",
            className="status-indicator",
            children=[
                #html.Div("✨ Clean Interactions Active", className="status-title"),
                #html.Div("Hover for subtle feedback", className="status-subtitle"),
            ],
        )

    def _build_graph_area(self) -> html.Div:
        """Build the graph visualization area."""
        return html.Div(
            children=[
                dcc.Graph(
                    id="dependency-graph",
                    figure=self.graph_builder.build_figure(),
                    config={
                        "displayModeBar": False,
                        "doubleClick": "reset",
                        "scrollZoom": False,
                        "staticPlot": False,
                    },
                    className="graph-container",
                )
            ],
            className="graph-area",
        )

    def _build_state_stores(self) -> html.Div:
        """Build state storage components."""
        return html.Div(
            children=[
                dcc.Store(id="sidebar-state", data={"collapsed": False}),
                dcc.Store(id="selected-domain", data="All"),
                dcc.Store(id="selected-node-store", data=None),
                dcc.Store(id="interaction-settings", data={"enabled": True}),
                dcc.Store(id="glow-settings", data={"enabled": False}),  # 👈 Default OFF
            ],
            style={"display": "none"},
        )

    def get_node_dimensions_for_js(self) -> Dict[str, Dict[str, Any]]:
        """
        Return node dimensions optimized for JavaScript interactions.

        Returns:
            Dict containing node dimensions and metadata
        """
        dimensions = {}
        for _, row in self.nodes_df.iterrows():
            width, height, wrapped_label = self.graph_builder.node_dimensions[
                row["DOMAIN_ID"]
            ]
            dimensions[row["DOMAIN_ID"]] = {
                "plotWidth": width,
                "plotHeight": height,
                "x_group": row["X_GROUP"],
                "tier": row["TIER_GROUP"],
                "maturity": row["CURRENT_MATURITY"],
                "label": row["DOMAIN_NAME"],
                "wrappedLabel": wrapped_label,
                "lineCount": wrapped_label.count("<br>") + 1,
            }
        return dimensions

    def get_domain_stats(self) -> Dict[str, Any]:
        """Get statistics about the domains and dependencies."""
        return {
            "total_nodes": len(self.nodes_df),
            "total_edges": len(self.edges_df),
            "tiers": self.nodes_df["TIER_GROUP"].unique().tolist(),
            "maturity_levels": sorted(self.nodes_df["CURRENT_MATURITY"].unique()),
            "x_groups": sorted(self.nodes_df["X_GROUP"].unique()),
        }
