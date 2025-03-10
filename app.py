import gradio as gr
import os
import json
import requests
from pathlib import Path

# Получаем переменные окружения
MINIO_URL = os.environ.get("MINIO_URL", "")
BUCKET_NAME = os.environ.get("BUCKET_NAME", "")
MODEL_NAME = os.environ.get("MODEL_NAME", "")
MODEL_VERSION = os.environ.get("MODEL_VERSION", "")

def predict(input_text):
    """Функция для выполнения предсказания модели"""
    try:
        # Здесь должна быть логика обращения к вашей модели
        # Это просто заглушка, замените на реальную логику
        result = {"input": input_text, "prediction": f"Предсказание для: {input_text}"}
        return json.dumps(result, ensure_ascii=False, indent=2)
    except Exception as e:
        return f"Ошибка: {str(e)}"

def display_model_info():
    """Отображение информации о модели"""
    info = {
        "MODEL_NAME": MODEL_NAME,
        "MODEL_VERSION": MODEL_VERSION,
        "MINIO_URL": MINIO_URL,
        "BUCKET_NAME": BUCKET_NAME
    }
    return json.dumps(info, ensure_ascii=False, indent=2)

# Создаем интерфейс Gradio
with gr.Blocks(title=f"Интерфейс модели {MODEL_NAME}") as demo:
    gr.Markdown(f"## 🤖 Интерфейс модели: {MODEL_NAME}")
    
    with gr.Tab("Предсказание"):
        with gr.Row():
            with gr.Column():
                input_text = gr.Textbox(label="Входные данные", lines=5)
                submit_btn = gr.Button("Выполнить предсказание")
            
            with gr.Column():
                output = gr.JSON(label="Результат")
        
        submit_btn.click(fn=predict, inputs=input_text, outputs=output)
    
    with gr.Tab("Информация о модели"):
        model_info = gr.JSON(label="Информация")
        refresh_btn = gr.Button("Обновить информацию")
        refresh_btn.click(fn=display_model_info, inputs=None, outputs=model_info)
        # Загружаем информацию при запуске
        demo.load(fn=display_model_info, inputs=None, outputs=model_info)

# Запускаем Gradio сервер
if __name__ == "__main__":
    port = int(os.environ.get("GRADIO_SERVER_PORT", 7860))
    demo.launch(server_name="0.0.0.0", server_port=port)
