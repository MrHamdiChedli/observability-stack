"""A small visit counter: just enough app to prove the whole infrastructure works."""
import os
import socket
import time

import psycopg2
from flask import Flask, Response, g, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

app = Flask(__name__)

REQUESTS = Counter(
    "http_requests_total", "HTTP requests handled", ["method", "endpoint", "status"]
)
LATENCY = Histogram(
    "http_request_duration_seconds", "Time spent handling a request", ["endpoint"]
)


def endpoint_label():
    # The route pattern, not the raw path: unknown URLs must not create new time series.
    return request.url_rule.rule if request.url_rule else "unknown"


@app.before_request
def start_timer():
    g.start = time.perf_counter()


@app.after_request
def record_metrics(response):
    if request.path != "/metrics":
        endpoint = endpoint_label()
        LATENCY.labels(endpoint).observe(time.perf_counter() - g.start)
        REQUESTS.labels(request.method, endpoint, str(response.status_code)).inc()
    return response


def db_password():
    """Reads the password from a Docker secret file if one is given, else from the environment."""
    path = os.environ.get("DB_PASSWORD_FILE")
    if path:
        with open(path, encoding="utf-8") as secret:
            return secret.read().strip()
    return os.environ["DB_PASSWORD"]


def connect():
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        dbname=os.environ.get("DB_NAME", "appdb"),
        user=os.environ.get("DB_USER", "app"),
        password=db_password(),
        connect_timeout=2,
    )


@app.get("/")
def index():
    """Counts the visit in the database and says which server answered."""
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO visits (id, total) VALUES (1, 1) "
            "ON CONFLICT (id) DO UPDATE SET total = visits.total + 1 "
            "RETURNING total"
        )
        total = cur.fetchone()[0]
    return jsonify(served_by=socket.gethostname(), visits=total)


@app.get("/healthz")
def healthz():
    """Returns 200 only if this server can really reach the database."""
    try:
        with connect() as conn, conn.cursor() as cur:
            cur.execute("SELECT 1")
    except psycopg2.OperationalError:
        return jsonify(status="database unreachable"), 503
    return jsonify(status="ok")


@app.get("/metrics")
def metrics():
    """Prometheus scrapes this endpoint."""
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)
