import gradio as gr
from transformers import pipeline, AutoTokenizer, AutoModelForQuestionAnswering
import os
import shutil

# Path where the model is stored
MODEL_ROOT_DIR = "/models"

# Ensure the models directory exists
if not os.path.exists(MODEL_ROOT_DIR):
    os.makedirs(MODEL_ROOT_DIR)

# Clean up any previous models before downloading a new one
for item in os.listdir(MODEL_ROOT_DIR):
    item_path = os.path.join(MODEL_ROOT_DIR, item)
    if os.path.isdir(item_path):
        print(f"🗑️ Removing old model: {item_path}")
        shutil.rmtree(item_path)

# Assuming the model is downloaded dynamically and extracted here
# We find the newly downloaded model folder inside /models
model_subdirs = [d for d in os.listdir(MODEL_ROOT_DIR) if os.path.isdir(os.path.join(MODEL_ROOT_DIR, d))]

if len(model_subdirs) == 0:
    raise ValueError("❌ No model found in /models. Please download a model first.")
elif len(model_subdirs) > 1:
    raise ValueError(f"⚠️ Multiple models found in /models: {model_subdirs}. Please keep only one.")

MODEL_DIR = os.path.join(MODEL_ROOT_DIR, model_subdirs[0])
print(f"✅ Using model from: {MODEL_DIR}")

# Load tokenizer and model
try:
    tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR)
    model = AutoModelForQuestionAnswering.from_pretrained(MODEL_DIR)
    qa_pipeline = pipeline("question-answering", model=model, tokenizer=tokenizer)
    print(f"✅ Model loaded successfully from {MODEL_DIR}")
except Exception as e:
    raise RuntimeError(f"❌ Model Load Error: {e}")

# Chatbot function
def chatbot(question, context):
    if not question or not context:
        return "❌ Please provide both a question and a context."

    try:
        response = qa_pipeline(question=question, context=context)
        return response["answer"]
    except Exception as e:
        return f"❌ Error: {str(e)}"

# Create Gradio UI
iface = gr.Interface(
    fn=chatbot,
    inputs=[gr.Textbox(label="Question"), gr.Textbox(label="Context")],
    outputs="text",
    title="Question Answering Chatbot",
    description="Ask a question based on the provided context."
)

# Launch Gradio
iface.launch(server_name="0.0.0.0", server_port=7860)
