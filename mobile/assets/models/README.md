Sherpa-ONNX model assets for MeshSetu.

Current expected model:

- `sherpa-onnx-zipformer-small-en-2023-06-26`

Download it from the official sherpa-onnx release page:

```bash
cd /Users/yashthakkar/Desktop/Hacks/SIH26/SIH26_-1xDevs/mobile/assets/models
curl -L -O https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-zipformer-small-en-2023-06-26.tar.bz2
tar xjf sherpa-onnx-zipformer-small-en-2023-06-26.tar.bz2
rm sherpa-onnx-zipformer-small-en-2023-06-26.tar.bz2
```

The Flutter app expects these files inside:

- `assets/models/sherpa-onnx-zipformer-small-en-2023-06-26/encoder-epoch-99-avg-1.int8.onnx`
- `assets/models/sherpa-onnx-zipformer-small-en-2023-06-26/decoder-epoch-99-avg-1.onnx`
- `assets/models/sherpa-onnx-zipformer-small-en-2023-06-26/joiner-epoch-99-avg-1.int8.onnx`
- `assets/models/sherpa-onnx-zipformer-small-en-2023-06-26/tokens.txt`

Only those four files are required for the current English STT integration.
