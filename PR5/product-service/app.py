from flask import Flask, jsonify
import os

app = Flask(__name__)
SERVICE_NAME = os.environ.get("SERVICE_NAME", "product-service")

PRODUCTS = [
    {"id": 1, "name": "Laptop",     "price": 75000, "stock": 10},
    {"id": 2, "name": "Smartphone", "price": 25000, "stock": 50},
    {"id": 3, "name": "Headphones", "price": 3000,  "stock": 100},
]

@app.route("/")
def home():
    return jsonify({"service": SERVICE_NAME, "status": "running"})

@app.route("/products")
def get_products():
    return jsonify({"service": SERVICE_NAME, "products": PRODUCTS})

@app.route("/products/<int:product_id>")
def get_product(product_id):
    p = next((p for p in PRODUCTS if p["id"] == product_id), None)
    if p:
        return jsonify(p)
    return jsonify({"error": "Product not found"}), 404

@app.route("/health")
def health():
    return jsonify({"status": "healthy", "service": SERVICE_NAME})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001)
