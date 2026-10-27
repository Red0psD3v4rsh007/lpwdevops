from flask import Flask, jsonify
import os

app = Flask(__name__)

# ── Read from ConfigMap (env vars) ─────────────────────────────────────────
APP_NAME    = os.environ.get("APP_NAME",    "pr7-config-app")
APP_ENV     = os.environ.get("APP_ENV",     "production")
LOG_LEVEL   = os.environ.get("LOG_LEVEL",   "INFO")
MAX_RETRIES = os.environ.get("MAX_RETRIES", "3")
DB_HOST     = os.environ.get("DB_HOST",     "localhost")
DB_PORT     = os.environ.get("DB_PORT",     "5432")

# ── Read from Secret (env vars) ────────────────────────────────────────────
DB_PASSWORD = os.environ.get("DB_PASSWORD", "NOT_SET")
API_KEY     = os.environ.get("API_KEY",     "NOT_SET")

@app.route("/")
def home():
    return jsonify({
        "app": APP_NAME,
        "environment": APP_ENV,
        "status": "running"
    })

@app.route("/config")
def config():
    """Shows non-sensitive config (from ConfigMap)."""
    return jsonify({
        "source": "ConfigMap",
        "APP_NAME":    APP_NAME,
        "APP_ENV":     APP_ENV,
        "LOG_LEVEL":   LOG_LEVEL,
        "MAX_RETRIES": MAX_RETRIES,
        "DB_HOST":     DB_HOST,
        "DB_PORT":     DB_PORT,
    })

@app.route("/secrets")
def secrets():
    """Shows that secrets are loaded (masked for security)."""
    return jsonify({
        "source": "Kubernetes Secret",
        "DB_PASSWORD": "****" if DB_PASSWORD != "NOT_SET" else "NOT_SET",
        "API_KEY":     "****" if API_KEY != "NOT_SET" else "NOT_SET",
        "secrets_loaded": DB_PASSWORD != "NOT_SET" and API_KEY != "NOT_SET"
    })

@app.route("/health")
def health():
    return jsonify({"status": "healthy", "app": APP_NAME})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
