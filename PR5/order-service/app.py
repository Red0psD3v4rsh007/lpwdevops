from flask import Flask, jsonify, request
import os, requests

app = Flask(__name__)
SERVICE_NAME = os.environ.get("SERVICE_NAME", "order-service")
PRODUCT_SERVICE_URL = os.environ.get("PRODUCT_SERVICE_URL", "http://product-service:5001")

ORDERS = []
ORDER_ID_COUNTER = [1]

@app.route("/")
def home():
    return jsonify({"service": SERVICE_NAME, "status": "running"})

@app.route("/orders", methods=["GET"])
def get_orders():
    return jsonify({"service": SERVICE_NAME, "orders": ORDERS})

@app.route("/orders", methods=["POST"])
def create_order():
    data = request.get_json()
    product_id = data.get("product_id")
    quantity   = data.get("quantity", 1)

    # Validate product via product-service
    try:
        resp = requests.get(f"{PRODUCT_SERVICE_URL}/products/{product_id}", timeout=3)
        product = resp.json()
        if "error" in product:
            return jsonify({"error": "Product not found"}), 404
    except Exception as e:
        return jsonify({"error": f"Could not reach product-service: {str(e)}"}), 503

    order = {
        "id":         ORDER_ID_COUNTER[0],
        "product_id": product_id,
        "product":    product.get("name"),
        "quantity":   quantity,
        "total":      product.get("price", 0) * quantity,
        "status":     "confirmed"
    }
    ORDERS.append(order)
    ORDER_ID_COUNTER[0] += 1
    return jsonify(order), 201

@app.route("/health")
def health():
    return jsonify({"status": "healthy", "service": SERVICE_NAME})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5002)
