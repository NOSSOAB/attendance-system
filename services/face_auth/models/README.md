# Models

## MediaPipe

Face Landmarker được tìm theo thứ tự:

1. `models/face_landmarker.task`

## Passive PAD MobileNetV3 ONNX

Backend dùng model nhẹ:

```text
models/anti-spoof-mn3.onnx
```

- Kiến trúc: MobileNetV3, đầu vào RGB `128x128`.
- Runtime: ONNX Runtime trên CPU; model không nằm trong APK.
- Nguồn: Open Model Zoo `anti-spoof-mn3`.
- Giấy phép model gốc: MIT.
- SHA-384 bắt buộc:

```text
6de4534964b723397b3e8c995cadcf43bc007cc2f9930b95ae25f76adccece5d1d4d058d0b15117b9e4a9f758424f92a
```

Tải lại model nếu cần:

```text
https://storage.openvinotoolkit.org/repositories/open_model_zoo/public/2022.1/anti-spoof-mn3/anti-spoof-mn3.onnx
```

Backend kiểm tra checksum trước khi nạp model. Thông tin license nằm trong
`anti-spoof-mn3.LICENSE.txt`. Model này chỉ phục vụ UI desktop legacy, không
được FastAPI production nạp. Có thể tải có kiểm tra checksum bằng:

```text
python scripts/fetch_models.py --include-legacy-pad
```

## InsightFace

Backend FastAPI nạp recognition model `w600k_r50.onnx`. Production config đặt
đường dẫn `/models/w600k_r50.onnx`; local config có thể đặt
`recognition.model_path` tới một đường dẫn khác. Sau khi clone, tải model vào
thư mục này bằng:

```text
python scripts/fetch_models.py
```

Script tải package `buffalo_l` từ release InsightFace, chỉ giải nén
`w600k_r50.onnx` và không đưa file model vào Git. Detection của InsightFace chỉ
được nạp khi chạy công cụ desktop/enrollment cũ; luồng điện thoại dùng năm điểm
căn chỉnh từ MediaPipe để tránh detect lại.
