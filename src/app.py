from flask import Flask, request, jsonify
from transformers import pipeline, AutoTokenizer, AutoModelForQuestionAnswering
import os
import logging

# Initialize Flask app
app = Flask(__name__)

# Enable logging for debugging
logging.basicConfig(level=logging.INFO)

# Path where the model is stored
MODEL_ROOT_DIR = "/models"

# Ensure the models directory exists
os.makedirs(MODEL_ROOT_DIR, exist_ok=True)

def load_model():
    """Loads the model from /models, ensuring only one is available."""
    model_subdirs = [d for d in os.listdir(MODEL_ROOT_DIR) if os.path.isdir(os.path.join(MODEL_ROOT_DIR, d))]
    
    if not model_subdirs:
        raise ValueError("❌ No model found in /models. Please download a model first.")
    
    MODEL_DIR = os.path.join(MODEL_ROOT_DIR, model_subdirs[0])
    logging.info(f"✅ Using model from: {MODEL_DIR}")

    try:
        tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR)
        model = AutoModelForQuestionAnswering.from_pretrained(MODEL_DIR)
        return pipeline("question-answering", model=model, tokenizer=tokenizer)
    except Exception as e:
        raise RuntimeError(f"❌ Model Load Error: {e}")

# Load the model
qa_pipeline = load_model()

@app.before_request
def log_request():
    """Logs incoming requests for debugging."""
    logging.info(f"📥 Received {request.method} request on {request.path}")

@app.route('/api/health', methods=['GET'])
def health_check():
    """Health check endpoint."""
    return jsonify({"status": "healthy"}), 200

@app.route('/api/predict', methods=['POST'])
def predict():
    """Handles question-answering predictions."""
    try:
        data = request.get_json()
        if not data or 'question' not in data or 'context' not in data:
            return jsonify({"error": "Missing required fields: 'question' and 'context'"}), 400

        response = qa_pipeline(question=data['question'], context=data['context'])

        return jsonify({
            "answer": response["answer"],
            "score": float(response["score"]),
            "start": response["start"],
            "end": response["end"]
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/info', methods=['GET'])
def model_info():
    """Returns model metadata if available."""
    model_subdirs = [d for d in os.listdir(MODEL_ROOT_DIR) if os.path.isdir(os.path.join(MODEL_ROOT_DIR, d))]
    if not model_subdirs:
        return jsonify({"error": "No model loaded"}), 404
    
    MODEL_DIR = os.path.join(MODEL_ROOT_DIR, model_subdirs[0])
    metadata_path = os.path.join(MODEL_DIR, "metadata.json")
    
    if os.path.exists(metadata_path):
        with open(metadata_path, 'r') as f:
            return jsonify(json.load(f)), 200
    else:
        return jsonify({"model_dir": MODEL_DIR}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
