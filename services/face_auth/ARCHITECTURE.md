# Báo cáo kiến trúc Face Auth Backend

> Phần “Cập nhật 21/07/2026” dưới đây là trạng thái hiện hành. Các số đo và mô tả
> Passive PAD ở phần lịch sử phía sau chỉ ghi lại phiên bản cũ ngày 18/07/2026;
> Passive PAD không còn nằm trong FastAPI backend.

## Cập nhật 21/07/2026

- InsightFace nhận dạng sau ba frame tốt và chạy song song với active liveness.
- Nếu nhận dạng sớm không đạt, backend tự thử lại bằng toàn bộ 6–12 frame tốt.
- Frame JPEG trùng byte bị loại khỏi liveness để giảm nguy cơ phát lại đơn giản.
- Mỗi hành động liveness yêu cầu baseline nhìn thẳng, độ trễ hành động tối thiểu và
  đúng thứ tự challenge ẩn.
- Mỗi session có token 256-bit; request status/frame/reset/delete phải gửi
  `X-Session-Token`.
- Danh sách identity và tạo session có thể bắt buộc `X-API-Key`; endpoint reload
  database bắt buộc `X-Admin-Key` và mặc định bị vô hiệu khi thiếu khóa.
- Session start và frame upload có token-bucket rate limit; health trả counter lỗi,
  overload và frame trùng.
- Embedding được lưu trong bảng `FaceIdentity` của PostgreSQL; backend không
  còn dùng `face_db.json` hay deserialize pickle trong deployment.
- Passive PAD cũ chỉ còn trong UI desktop legacy, không được container FastAPI nạp.
- EC2 test giới hạn ba session, một detector và một recognition worker.

Luồng hiện tại:

```text
Android + API key
  -> tạo session + nhận session token
  -> JPEG mới -> MediaPipe + active liveness
                 \-> đủ 3 frame tốt -> InsightFace chạy sớm
  -> liveness PASS + identity PASS -> SUCCESS
  -> identity sớm FAIL -> retry toàn bộ frame -> SUCCESS/FAILED
```

## Lịch sử thiết kế ngày 18/07/2026

Ngày thực hiện: 18/07/2026

## 1. Kết luận kiến trúc

Hệ thống được thiết kế lại thành **modular monolith chạy trên một PC**. Đây là lựa chọn phù hợp hơn microservice cho demo local: chỉ nạp một bộ model, không sao chép hàng GB RAM, không thêm message broker hay Redis, nhưng các trách nhiệm vẫn tách rõ để dễ sửa và test.

```text
Android thin client
  camera + JPEG + REST + render
              |
              v
FastAPI routes (/api/v1)
              |
              v
AuthenticationPipeline (state machine)
   |                 |                  |
   v                 v                  v
SessionStore      MediaPipe       Bounded verification workers
(TTL/lock)       mỗi frame       Multi-frame PAD -> InsightFace
```

APK tuyệt đối không chứa hoặc chạy MediaPipe, PyTorch, ONNX Runtime hay model khuôn mặt. Việc nén JPEG, gửi HTTP và hiển thị là trách nhiệm frontend, không phải AI inference.

## 2. Vấn đề của phiên bản cũ

- `api_server.py` gom route, session, orientation, inference và serialize vào một file lớn.
- Mỗi frame chạy MediaPipe ở cả bốn hướng, kể cả khi hướng camera không đổi.
- CPU inference chạy trực tiếp trong coroutine FastAPI, có thể chặn event loop.
- Anti-spoof và recognition được gọi lặp lại khi liveness chưa hoàn thành.
- InsightFace chạy hai lần trên full frame và crop rồi chọn kết quả tốt hơn.
- Sau liveness PASS, request chờ nhiều giây nên người dùng thấy ứng dụng bị đơ.
- Session là dictionary không có TTL và không giới hạn số lượng.
- Điện thoại decode JPEG thành Bitmap, rotate, mirror rồi encode JPEG lần hai cho từng frame.
- Tần suất 850 ms/frame dễ bỏ lỡ thao tác chớp mắt.
- Dependency mặc định chứa nhiều package của web UI/training mà backend không dùng.

## 3. Thành phần mới

| Thành phần | Trách nhiệm |
|---|---|
| `backend/app.py` | FastAPI lifespan, nạp/dọn model và nối dependency |
| `backend/routes.py` | HTTP validation, API v1, backpressure, endpoint legacy |
| `backend/pipeline.py` | State machine và điều phối liveness/verify/final |
| `backend/frame_processor.py` | Decode, orientation cache, quality/best-frame selection |
| `backend/presenter.py` | Serialize domain state thành response JSON ổn định |
| `backend/runtime.py` | Sở hữu ba model, lock native runtime, reload face database |
| `backend/session_store.py` | TTL 5 phút, giới hạn 32 session, dọn session hết hạn |
| `backend/domain.py` | Trạng thái và dữ liệu một phiên xác thực |
| `backend/settings.py` | Chuyển YAML thành cấu hình backend có kiểu rõ ràng |

`api_server.py` chỉ còn là compatibility shim nên lệnh cũ vẫn hoạt động.

## 4. Các quyết định tối ưu chính

### Hiệu chỉnh hướng một lần

Nếu client chưa biết rotation, backend thử bốn hướng ở frame đầu có mặt và cache kết quả trong session. Các frame tiếp theo chỉ chạy một hướng. Client mới gửi JPEG camera thô với `rotation_degrees=-1` và `mirror=true`.

### Active liveness và passive PAD nhiều frame

Trong `LIVENESS`, MediaPipe kiểm tra ba hành động ngẫu nhiên và backend giữ tối đa 12 frame JPEG nén. Mỗi challenge yêu cầu trạng thái mặt thẳng trước khi ghi nhận chuyển động. Khi active liveness PASS:

1. Session chuyển ngay sang `VERIFYING`.
2. Response trả về điện thoại mà không chờ model nặng.
3. Worker chạy MobileNetV3 ONNX PAD trên tối đa 8 frame.
4. Nếu passive PAD đạt, InsightFace chạy trên 3 frame đại diện.
5. Năm điểm căn chỉnh từ MediaPipe được dùng trực tiếp, tránh chạy detector InsightFace lần nữa.
6. APK dừng upload và poll endpoint session.

Cơ chế này vừa giảm CPU vừa sửa đúng lỗi “PASS liveness xong bị đơ”.

### Quản lý tải và thread

- Model nạp đúng một lần bằng FastAPI lifespan.
- Frame CPU-bound chạy trong threadpool, không chạy trên event loop.
- Semaphore giới hạn số frame đồng thời và trả HTTP `429` khi hàng đợi đầy.
- Khóa riêng mỗi session ngăn hai frame cập nhật cùng một challenge.
- Hàng đợi verification có giới hạn; server từ chối sớm khi đủ worker và queue đã đầy.
- MediaPipe, PAD và recognition có lock riêng. Recognition giữ một worker ổn định vì benchmark hai lượt đồng thời trên cùng CPU gây tranh tài nguyên nghiêm trọng.
- Chỉ chạy Uvicorn `--workers 1` trong bản local để không nhân bản model và session.

### Android là thin client

Client dùng CameraX 1.6.1, `ImageAnalysis` 640x480 và `KEEP_ONLY_LATEST`. Nó chỉ thực hiện `NV21 -> JPEG` một lần; rotation/mirror được PC xử lý. Tần suất tối đa là 250 ms/frame và chỉ có một request frame in-flight.

## 5. State machine

```text
LIVENESS
  | pass                         | timeout/retry exhausted
  v                              v
VERIFYING                      FAILED
  | real + identity pass         | spoof / mismatch / model error
  v                              v
SUCCESS                        FAILED
```

Mỗi job verification mang theo `generation`. Khi reset session, generation tăng; kết quả job cũ không thể ghi đè phiên mới.

## 6. Hợp đồng API v1

- `GET /api/v1/health`: readiness, identities, uptime, số session.
- `GET /api/v1/identities`: danh sách người từ PC.
- `POST /api/v1/sessions`: tạo phiên với `target_name`.
- `POST /api/v1/sessions/{id}/frames`: gửi multipart JPEG.
- `GET /api/v1/sessions/{id}`: poll trạng thái, không chạy inference.
- `POST /api/v1/sessions/{id}/reset`: sinh challenge mới.
- `DELETE /api/v1/sessions/{id}`: giải phóng session.

Endpoint cũ vẫn map vào cùng service, không còn logic trùng lặp.

## 7. Số đo trên máy hiện tại

Các số dưới đây dùng ảnh test hiện có trên máy; chúng là benchmark kỹ thuật, không phải SLA sản phẩm.

| Phép đo | Cũ | Mới | Kết quả |
|---|---:|---:|---:|
| MediaPipe detect phần orientation | 41.3 ms (4 hướng) | 4.4 ms (1 hướng) | nhanh hơn 9.29 lần ở phần detector |
| API frame auto-orientation | thử bốn hướng mỗi frame | 101.5 ms lần đầu, 26.3 ms frame cache | chi phí orientation chỉ trả một lần |
| Frame kết thúc liveness | chờ cả model nặng | trả `VERIFYING` sau 66.1 ms | UI không còn đứng chờ |
| PAD 8 frame + recognition 3 frame | một frame Silent-Face + detect InsightFace | khoảng 1.28 giây trên CPU với mẫu hiện có | nhiều frame nhưng vẫn đủ nhẹ |
| Model startup | nạp nhiều model không dùng | khoảng 3.64 giây | chỉ nạp recognition ONNX cần thiết |

E2E smoke test với ảnh `person_A` trả Real `99.88%`, similarity `99.67%` và kết quả `SUCCESS`. Đây chỉ xác nhận pipeline hoạt động, không chứng minh khả năng chống giả mạo thực tế.

## 8. Dependency và vận hành

`requirements-backend.txt` đã bỏ khỏi cài đặt mặc định:

- Streamlit
- matplotlib
- scikit-learn
- albumentations
- prettytable

`requirements-legacy-ui.txt` giữ Streamlit dưới dạng tùy chọn. `run_backend.bat` nhận biết tiến trình Face Auth cũ trên port 8000 và chỉ dừng đúng tiến trình Uvicorn liên quan; nó không tùy tiện kill ứng dụng khác.

Môi trường Python global hiện có package `rembg` không thuộc project và package đó yêu cầu NumPy mới hơn, trong khi MediaPipe stack đang dùng NumPy 1.26.4. Backend đã chạy ổn; `install_pc_dependencies.bat` nay tạo `.venv` riêng để những lần cài tiếp theo không bị xung đột global này.

## 9. Kiểm thử đã chạy

- Python compile toàn bộ package backend: PASS.
- Unit test TTL session: PASS.
- Unit test orientation chỉ calibrate một lần: PASS.
- Unit test verification chạy nền: PASS.
- FastAPI startup + health + identity API: PASS.
- E2E create session -> frame -> poll -> final: PASS.
- Gradle `:app:assembleDebug`: PASS.
- Pool benchmark thật: 3 MediaPipe worker đạt khoảng 91 FPS so với 55 FPS với một worker trên máy hiện tại.
- Pool benchmark thật: 3 ArcFace ONNX session đạt khoảng 9.39 embedding/giây so với 3.50 với một session.
- HTTP load test: tạo 100 session đồng thời, `100/100` được chấp nhận trong 0.163 giây.
- Model load test 100 phiên, concurrency 25: `100/100 SUCCESS`, p95 10.78 giây.
- Model load test 100 phiên, concurrency 100: `100/100 SUCCESS`, p95 41.37 giây; cần scale ngang để đạt SLA thấp hơn.

## 10. Giới hạn còn lại

- Đây là demo LAN, chưa có TLS, token/API key, rate limit theo thiết bị hay mã hóa biometric database.
- Session vẫn nằm trong RAM. Scale ngang hiện dùng một process mỗi EC2 và ALB stickiness; Redis/database là bước cần thiết nếu muốn failover phiên giữa các EC2.
- `mobile_real_face_threshold=0.35` là ngưỡng demo đã hạ cho camera hiện tại. Cần hiệu chuẩn bằng tập real/print/replay đủ lớn trước khi dùng thật.
- Background có poster/gương chứa mặt có thể làm tăng `face_count`; UI nên hướng dẫn dùng nền sạch.
- Android đã dùng CameraX nhưng vẫn là thin client; APK không chứa model AI.
- Presentation attack detection phụ thuộc camera, ánh sáng và miền dữ liệu; không nên gọi bản demo này là đạt chuẩn ngân hàng.

## 11. Tài liệu kỹ thuật đã tham khảo

- FastAPI khuyến nghị dùng lifespan để quản lý tài nguyên/model dùng chung: https://fastapi.tiangolo.com/advanced/events/
- FastAPI `UploadFile` cho multipart upload: https://fastapi.tiangolo.com/tutorial/request-files/
- MediaPipe Face Landmarker có IMAGE/VIDEO/LIVE_STREAM và cơ chế giảm latency: https://ai.google.dev/edge/api/mediapipe/python/mp/tasks/vision/FaceLandmarker
- ONNX Runtime hướng dẫn tránh tranh chấp thread giữa nhiều session: https://onnxruntime.ai/docs/performance/tune-performance/threading.html
- Open Model Zoo anti-spoof-mn3: https://docs.openvino.ai/2023.3/omz_models_model_anti_spoof_mn3.html
- CameraX ImageAnalysis/backpressure: https://developer.android.com/media/camera/camerax/analyze
