
import os
from flask import Flask, request, jsonify
from flask_cors import CORS
from PIL import Image
from transformers import BlipProcessor, BlipForQuestionAnswering, AutoImageProcessor, AutoTokenizer, VisionEncoderDecoderModel
import io
import av
import numpy as np
import torch
import torch.quantization
import tempfile
import logging
from pyngrok import ngrok

ngrok.set_auth_token("2e1rwbupsn5xwgSnPwmDcO365Xq_4qNZ8jVd6PwCXYi2A6ijG")

app = Flask(__name__)
CORS(app)  # Enable CORS for all routes

# Configure logging
logging.basicConfig(level=logging.INFO)

# Image VQA model
vqa_processor = BlipProcessor.from_pretrained("Salesforce/blip-vqa-capfilt-large")
vqa_model = BlipForQuestionAnswering.from_pretrained("Salesforce/blip-vqa-capfilt-large")

# Video captioning model
device = "cuda" if torch.cuda.is_available() else "cpu"
image_processor = AutoImageProcessor.from_pretrained("notbdq/videogpt")
tokenizer = AutoTokenizer.from_pretrained("notbdq/videogpt")
video_model = VisionEncoderDecoderModel.from_pretrained("notbdq/videogpt")

# Quantize the video model
video_model.eval()
video_model = torch.quantization.quantize_dynamic(
    video_model, {torch.nn.Linear, torch.nn.Conv2d}, dtype=torch.qint8
)
video_model = video_model.to(device)

def process_video(video_path):
    container = av.open(video_path)
    clip_len = 4
    seg_len = container.streams.video[0].frames
    indices = set(np.linspace(0, seg_len, num=clip_len, endpoint=False).astype(np.int64))
    frames = []
    container.seek(0)
    for i, frame in enumerate(container.decode(video=0)):
        if i in indices:
            frames.append(frame.to_ndarray(format="rgb24"))

    target_size = (224, 224)
    frames = [np.array(Image.fromarray(frame).resize(target_size)) for frame in frames]

    gen_kwargs = {
        "max_length": 16,
        "num_beams": 1,
        "temperature": 0.3
    }

    pixel_values = image_processor(frames, return_tensors="pt").pixel_values.to(device)
    with torch.no_grad():
        tokens = video_model.generate(pixel_values, **gen_kwargs)
        caption = tokenizer.batch_decode(tokens, skip_special_tokens=True)[0]
    return caption

@app.route('/vqa', methods=['POST'])
def vqa():
    app.logger.info("VQA endpoint called")
    if 'image' not in request.files or 'question' not in request.form:
        app.logger.error("Missing image or question")
        return jsonify({'error': 'Missing image or question'}), 400

    image_file = request.files['image']
    question = request.form['question']

    app.logger.info(f"Received question: {question}")

    image_bytes = image_file.read()
    raw_image = Image.open(io.BytesIO(image_bytes)).convert('RGB')

    inputs = vqa_processor(raw_image, question, return_tensors="pt")
    out = vqa_model.generate(**inputs, max_length=100)
    answer = vqa_processor.decode(out[0], skip_special_tokens=True)

    app.logger.info(f"Generated answer: {answer}")

    return jsonify({'answer': answer})

@app.route('/caption', methods=['POST'])
def caption_video():
    app.logger.info("Caption endpoint called")
    if 'video' not in request.files:
        app.logger.error("No video file provided")
        return jsonify({'error': 'No video file provided'}), 400

    video_file = request.files['video']

    with tempfile.NamedTemporaryFile(delete=False, suffix='.mp4') as tmp_file:
        video_file.save(tmp_file.name)
        tmp_filename = tmp_file.name

    try:
        caption = process_video(tmp_filename)
        app.logger.info(f"Generated caption: {caption}")
        return jsonify({'caption': caption})
    except Exception as e:
        app.logger.error(f"Error processing video: {str(e)}")
        return jsonify({'error': str(e)}), 500
    finally:
        os.unlink(tmp_filename)

if __name__ == '__main__':
    # Use this for local development
    # app.run(host='0.0.0.0', port=5000, debug=True)

    port = 5000
    public_url = ngrok.connect(port).public_url
    print(f" * ngrok tunnel "{public_url}" -> "http://127.0.0.1:{port}"")

    # Update any base_url with the public_url
    app.config['BASE_URL'] = public_url

    # Run the app
    app.run(port=port)
