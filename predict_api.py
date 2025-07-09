import os
from flask import Flask, request, jsonify
import joblib  
import sklearn  
import numpy as np
from flask_cors import CORS
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
model_path = os.path.join(BASE_DIR, "model", "category_model.pkl")
vectorizer_path = os.path.join(BASE_DIR, "model", "vectorizer.pkl")

model = joblib.load(model_path)
vectorizer = joblib.load(vectorizer_path)

app = Flask(__name__)
CORS(app)
@app.route("/api/predict", methods=["POST"])
def predict():
    data = request.json
    description = data.get("description", "")

    if not description:
        return jsonify({"error": "Description is required"}), 400

    # Preprocess and predict
    X = vectorizer.transform([description])
    prediction = model.predict(X)[0]

    return jsonify({"category": prediction})

if __name__ == "__main__":
  
    app.run(host="0.0.0.0", port=5000)
