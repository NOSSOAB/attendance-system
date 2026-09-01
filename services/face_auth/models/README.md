# Model

## MediaPipe

Face Landmarker dùng file `models/face_landmarker.task`.

## InsightFace

Khi chạy trực tiếp bằng Python, tải model bằng lệnh:

```powershell
python scripts/fetch_models.py
```

Khi dùng Docker Compose, Dockerfile tự tải model trong quá trình build.

## Model kiểm tra sống cũ

Model này chỉ dùng cho công cụ cũ trên máy tính:

```powershell
python scripts/fetch_models.py --include-legacy-pad
```

Kiểm tra giấy phép của từng model trước khi sử dụng.
