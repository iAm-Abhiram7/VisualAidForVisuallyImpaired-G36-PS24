'''from fastapi import FastAPI, File, UploadFile, Form
from fastapi.responses import JSONResponse
from PIL import Image
from transformers import BlipProcessor, BlipForQuestionAnswering
import io

app = FastAPI()
processor = BlipProcessor.from_pretrained("Salesforce/blip-vqa-capfilt-large")
model = BlipForQuestionAnswering.from_pretrained("Salesforce/blip-vqa-capfilt-large")

@app.post("/chat")
async def chat(question: str = Form(...), image: UploadFile = File(...)):
    image_content = await image.read()
    raw_image = Image.open(io.BytesIO(image_content)).convert('RGB')
    inputs = processor(raw_image, question, return_tensors="pt")    
    out = model.generate(**inputs)
    answer = processor.decode(out[0], skip_special_tokens=True)    
    return JSONResponse(content={"response": answer})

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
'''

'''
from PIL import Image
from transformers import BlipProcessor, BlipForQuestionAnswering

processor = BlipProcessor.from_pretrained("Salesforce/blip-vqa-capfilt-large")
model = BlipForQuestionAnswering.from_pretrained("Salesforce/blip-vqa-capfilt-large")

img_url = './cat.jpg' 
raw_image = Image.open(img_url).convert('RGB')

question = "how many cats are in the picture?"
inputs = processor(raw_image, question, return_tensors="pt")

out = model.generate(**inputs)
print(processor.decode(out[0], skip_special_tokens=True))
'''

from flask import Flask, request, jsonify
from PIL import Image
from transformers import BlipProcessor, BlipForQuestionAnswering
import io

app = Flask(__name__)

processor = BlipProcessor.from_pretrained("Salesforce/blip-vqa-capfilt-large")
model = BlipForQuestionAnswering.from_pretrained("Salesforce/blip-vqa-capfilt-large")

@app.route('/vqa', methods=['POST'])
def vqa():
    if 'image' not in request.files or 'question' not in request.form:
        return jsonify({'error': 'Missing image or question'}), 400

    image_file = request.files['image']
    question = request.form['question']
    image_bytes = image_file.read()
    raw_image = Image.open(io.BytesIO(image_bytes)).convert('RGB')
    inputs = processor(raw_image, question, return_tensors="pt")
    out = model.generate(**inputs, max_length=100)
    answer = processor.decode(out[0], skip_special_tokens=True)

    return jsonify({'answer': answer})

if __name__ == '__main__':
    app.run(debug=True)