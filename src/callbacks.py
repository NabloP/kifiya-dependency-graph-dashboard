from dash import Input, Output, State, ctx
from dash.exceptions import PreventUpdate
from .graph_builder import GraphBuilder
from typing import Optional, List, Dict, Tuple


class CallbackRegistrar:
    def __init__(self, app, graph_builder: GraphBuilder):
        self.app = app
        self.graph_builder = graph_builder

    def _extract_node_id(self, click_data: Optional[Dict]) -> Optional[str]:
        point = (click_data or {}).get("points", [{}])[0]
        node_id = point.get("customdata")
        return None if node_id in [None, "__background__", "RESET"] else node_id

    def _extract_hover_node_id(self, hover_data: Optional[Dict]) -> Optional[str]:
        node_id = (hover_data or {}).get("points", [{}])[0].get("customdata")
        return None if node_id in [None, "__background__", "RESET"] else node_id

    def _validate_directions(self, directions: Optional[List[str]]) -> List[str]:
        valid = {"upstream", "downstream"}
        return [d for d in (directions or valid) if d in valid] or list(valid)

    def register_callbacks(self):
        # Main selection callback
        @self.app.callback(
            Output("selected-domain", "data"),
            Output("domain-selector", "value"),
            Output("selected-node-store", "data"),
            Input("domain-selector", "value"),
            Input("dependency-graph", "clickData"),
            Input("dependency-graph", "relayoutData"),
            Input("reset-button", "n_clicks"),
            Input("mode-toggle", "value"),
            State("selected-node-store", "data"),
            prevent_initial_call=True,
        )
        def sync_selection(drop_val, click_data, relayout_data, _, mode, _current):
            triggered = ctx.triggered_id
            if mode == "interactive":
                if triggered == "reset-button" or relayout_data == {"autosize": True}:
                    return "All", "All", None
                node_id = self._extract_node_id(click_data)
                return (node_id, node_id, node_id) if node_id else ("All", "All", None)
            else:
                val = drop_val or "All"
                return val, val, None if val == "All" else val

        # Graph rendering callback
        @self.app.callback(
            Output("dependency-graph", "figure"),
            Input("selected-node-store", "data"),
            Input("direction-toggle", "value"),
            Input("mode-toggle", "value"),
            Input("dependency-graph", "hoverData"),
        )
        def update_graph(selected_node, directions, mode, hover_data):
            selected = None if selected_node in (None, "All") else selected_node
            hovered = self._extract_hover_node_id(hover_data)
            return self.graph_builder.build_figure(
                selected=selected,
                directions=self._validate_directions(directions),
                mode=mode,
                hovered=hovered,
            )

        # Sidebar toggle
        @self.app.callback(
            Output("sidebar-container", "style"),
            Output("collapse-button", "children"),
            Output("sidebar-state", "data"),
            Input("collapse-button", "n_clicks"),
            State("sidebar-state", "data"),
            prevent_initial_call=True,
        )
        def toggle_sidebar(_, state):
            collapsed = not (state or {}).get("collapsed", False)
            style = {
                "width": "0px" if collapsed else "250px",
                "padding": "0px" if collapsed else "12px 16px",
                "borderRight": "none" if collapsed else "1px solid #e0e0e0",
                "backgroundColor": "#fafafa" if not collapsed else "transparent",
                "overflow": "hidden",
                "flexShrink": 0,
                "transition": "all 0.3s ease",
                "borderTopRightRadius": "8px" if not collapsed else "0px",
            }
            return style, "⇥" if collapsed else "⇤", {"collapsed": collapsed}

        # Mode toggle visibility
        @self.app.callback(
            Output("dropdown-wrapper", "style"),
            Output("reset-wrapper", "style"),
            Input("mode-toggle", "value"),
        )
        def toggle_mode_visibility(mode: str):
            base_style = {"marginBottom": "16px"}
            if mode == "interactive":
                return (
                    {**base_style, "display": "none"},
                    {**base_style, "display": "block"},
                )
            return (
                {**base_style, "display": "block"},
                {**base_style, "display": "none"},
            )

        # ✅ Glow toggle logic — default OFF on initial load
        @self.app.callback(
            Output("glow-settings", "data"),
            Input("glow-toggle", "value"),
        )
        def toggle_glow(value):
            if value is None:
                return {"enabled": False}
            return {"enabled": "enabled" in value}
