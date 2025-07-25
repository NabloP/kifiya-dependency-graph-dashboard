# src/app.py

import sys
import os
from dash import Dash

# Add src to Python path
project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, project_root)

from src.layout import LayoutBuilder
from src.callbacks import CallbackRegistrar

# Paths to data files
nodes_path = os.path.join(os.path.dirname(__file__), '..', 'data', 'domain_nodes.csv')
edges_path = os.path.join(os.path.dirname(__file__), '..', 'data', 'domain_dependencies.csv')

# Initialize Dash app
app = Dash(__name__, suppress_callback_exceptions=True)
app.config.suppress_callback_exceptions = True
app.config.prevent_initial_callbacks = "initial_duplicate"
app.title = "Kifiya Maturity Dependency Graph"

# Layout
layout_builder = LayoutBuilder(nodes_path, edges_path)
app.layout = layout_builder.create_layout(app)

# Callbacks
callback_registrar = CallbackRegistrar(app, layout_builder.graph_builder)
callback_registrar.register_callbacks()

# --- CRITICAL FOR DEPLOYMENT ---
# This line exposes the underlying Flask server that Gunicorn (or similar) will use.
server = app.server
