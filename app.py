import os
from flask import Flask, jsonify, render_template

app = Flask(__name__)
APP_VERSION = os.environ.get("APP_VERSION", "v1")

@app.get("/")
def home():
    return render_template("index.html", version=APP_VERSION)

@app.get("/health")
def health():
    return jsonify(status="healthy", version=APP_VERSION), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
