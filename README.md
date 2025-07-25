# Kifiya Maturity Dependency Graph

An interactive Dash application designed to visualize the Kifiya Maturity Dependency Graph. This tool enables users to explore relationships between domain nodes and their dependencies with modern, clean UI interactions for enhanced usability.

## ✨ Features

* **Interactive Dependency Graph**: Visualize complex relationships between various domain nodes.
* **Clean UI Interactions**: Enjoy subtle hover effects, clear selection states, and high-performance interactions inspired by modern UIs.
* **Filter & Explore**: Easily navigate and understand the maturity dependencies within the Kifiya ecosystem.
* **Responsive Design**: Optimized for various screen sizes, ensuring a consistent experience across devices.

## 🚀 Getting Started

Follow these steps to set up and run the application locally.

### Prerequisites

* Python 3.8+
* `pip` (Python package installer)

### 1. Clone the Repository

```bash
git clone [https://github.com/NabloP/kifiya-maturity-graph.git](https://github.com/NabloP/kifiya-maturity-graph.git)
cd kifiya-maturity-graph
```

### 2. Create a Virtual Environment

It's highly recommended to use a virtual environment to manage dependencies.

```
python -m venv venv
```

On Windows:
```
.\venv\Scripts\activate
```

On macOS/Linux:
```
source venv/bin/activate
```

### 3. Install Dependencies

Install all required Python packages using the `requirements.txt` file:

```
pip install -r requirements.txt
```

### 4. Run the Application Locally

Navigate to the project root and run the `app.py` file.

```
python src/app.py
```

The application will typically be available at `http://127.0.0.1:8050/` in your web browser.

## 📁 Project Structure

```
kifiya-maturity-graph/
├── data/
│   ├── domain_nodes.csv          # Contains data for graph nodes
│   └── domain_dependencies.csv   # Contains data for graph edges (dependencies)
├── src/
│   ├── init.py               # Makes 'src' a Python package
│   ├── app.py                    # Main Dash application file
│   ├── layout.py                 # Defines the layout of the Dash app
│   ├── callbacks.py              # Contains all Dash callbacks for interactivity
│   └── assets/                   # Static files (CSS, JS) automatically served by Dash
│       ├── clean-interactions.css
│       └── clean-interactions.js
├── .gitignore                    # Specifies intentionally untracked files to ignore
├── requirements.txt              # Lists Python dependencies
└── Procfile                      # Defines the command to run the app on deployment platforms
```

## ☁️ Deployment

This application is configured for easy deployment on platforms like [Render](https://render.com/), which offers a generous free tier.

The key files for deployment are:

* **`requirements.txt`**: Lists all necessary Python packages, including `gunicorn` (a production-ready WSGI HTTP server).

* **`Procfile`**: Specifies how the web server should run your application. For this project, it contains:

```
web: gunicorn src.app:server
```

This tells Render to run `gunicorn`, looking for the `server` object within `app.py` inside the `src` package.

* **`src/app.py`**: Includes the `server = app.server` line, which exposes the underlying Flask server for `gunicorn` to connect to.

### Steps for Render Deployment:

1. **Prepare your project**: Ensure your `src/app.py` has `server = app.server` and no `if __name__ == "__main__":` block. Verify `requirements.txt` and `Procfile` are in the root, and `src/__init__.py` exists.

2. **Push to GitHub**: Commit all your project files to a public GitHub repository.

3. **Create Web Service on Render**:

 * Go to [Render.com](https://render.com/) and create a new Web Service.

 * Connect your GitHub repository.

 * Set the **Build Command** to: `pip install -r requirements.txt`

 * Set the **Start Command** to: `gunicorn src.app:server`

 * Choose the "Free" instance type.

4. **Deploy**: Render will automatically build and deploy your application. Monitor the deployment logs for any issues.

## 🛠️ Technologies Used

* **Python**

* **Dash** (Plotly)

* **Pandas**

* **NumPy**

* **NetworkX**

* **Plotly Graph Objects**

* **Gunicorn** (for deployment)

* **HTML, CSS, JavaScript** (for custom interactions and styling)

## 🙏 Acknowledgements

* Inspired by modern UI/UX principles for interactive visualizations.

* Built using the powerful Dash framework by Plotly.