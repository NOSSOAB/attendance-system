package com.faceauth.thinclient;

import android.Manifest;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.os.Build;
import android.os.Bundle;
import android.text.InputType;
import android.util.Size;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.TextView;

import androidx.activity.ComponentActivity;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.NonNull;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ImageProxy;
import androidx.camera.core.Preview;
import androidx.camera.core.resolutionselector.ResolutionSelector;
import androidx.camera.core.resolutionselector.ResolutionStrategy;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.core.content.ContextCompat;

import com.google.common.util.concurrent.ListenableFuture;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.CookieHandler;
import java.net.CookieManager;
import java.net.CookiePolicy;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

public class MainActivity extends ComponentActivity {
    private static final String EC2_FACE_API_BASE_URL = "http://18.143.149.146/face-api";
    private static final long MIN_FRAME_INTERVAL_MS = 250;
    private static final long MAX_FRAME_INTERVAL_MS = 2000;
    private static final long VERIFY_POLL_INTERVAL_MS = 350;
    private static final long VERIFY_POLL_MAX_BACKOFF_MS = 3000;
    private static final long VERIFY_TIMEOUT_MS = 60000;
    private static final int JPEG_QUALITY = 68;

    private EditText serverUrlInput;
    private EditText apiKeyInput;
    private Spinner peopleSpinner;
    private TextView statusText;
    private TextView challengeText;
    private TextView scoreText;
    private PreviewView previewView;

    private final ExecutorService networkExecutor = Executors.newSingleThreadExecutor();
    private final ExecutorService cameraExecutor = Executors.newSingleThreadExecutor();
    private final List<String> people = new ArrayList<>();
    private final ActivityResultLauncher<String> cameraPermissionLauncher =
            registerForActivityResult(
                    new ActivityResultContracts.RequestPermission(),
                    granted -> {
                        if (Boolean.TRUE.equals(granted)) {
                            startCamera();
                        } else {
                            setStatus("Không có quyền camera.");
                        }
                    }
            );

    private ProcessCameraProvider cameraProvider;
    private final Object sessionStateLock = new Object();
    private volatile boolean streaming = false;
    private volatile boolean destroyed = false;
    private volatile SessionContext activeSession = null;
    private final SessionOperationGuard sessionOperations = new SessionOperationGuard();
    // A second slot lets a replacement session poll immediately even if the
    // cancelled session is still leaving a blocked socket read.
    private final ExecutorService pollingExecutor = Executors.newFixedThreadPool(2);

    private static final class SessionContext {
        final long operationId;
        final String serverUrl;
        final String apiKey;
        final String sessionId;
        final String sessionToken;
        final AtomicBoolean cancelled = new AtomicBoolean(false);
        final AtomicBoolean sendingFrame = new AtomicBoolean(false);
        final AtomicBoolean pollingVerification = new AtomicBoolean(false);
        volatile long frameIntervalMs = MIN_FRAME_INTERVAL_MS;
        volatile long lastFrameSentAt = 0L;

        SessionContext(
                long operationId,
                String serverUrl,
                String apiKey,
                String sessionId,
                String sessionToken
        ) {
            this.operationId = operationId;
            this.serverUrl = serverUrl;
            this.apiKey = apiKey;
            this.sessionId = sessionId;
            this.sessionToken = sessionToken;
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // Preserve ALB affinity cookies so every request in one liveness session
        // reaches the same EC2 target when the backend is scaled horizontally.
        CookieHandler.setDefault(new CookieManager(null, CookiePolicy.ACCEPT_ALL));
        buildUi();
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            cameraPermissionLauncher.launch(Manifest.permission.CAMERA);
        } else {
            startCamera();
        }
    }

    private void buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(18, 18, 18, 18);

        TextView appTitle = label("Face Auth EC2 Test 2.0.1");
        appTitle.setTextSize(20);
        root.addView(appTitle);

        serverUrlInput = new EditText(this);
        serverUrlInput.setSingleLine(true);
        String savedServerUrl = getSharedPreferences("face_auth", MODE_PRIVATE)
                .getString("server_url", EC2_FACE_API_BASE_URL);
        serverUrlInput.setText(savedServerUrl);
        root.addView(label("API EC2 (có thể sửa khi cần)"));
        root.addView(serverUrlInput, matchWrap());

        apiKeyInput = new EditText(this);
        apiKeyInput.setSingleLine(true);
        apiKeyInput.setInputType(
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD
        );
        apiKeyInput.setSaveEnabled(false);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            apiKeyInput.setImportantForAutofill(
                    android.view.View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
            );
        }
        // Remove plaintext keys left behind by versions older than 2.0.1.
        getSharedPreferences("face_auth", MODE_PRIVATE)
                .edit()
                .remove("api_key")
                .apply();
        // Never persist the shared client key in plaintext on the device.
        apiKeyInput.setText("");
        root.addView(label("Mã truy cập API (không lưu trên máy)"));
        root.addView(apiKeyInput, matchWrap());

        LinearLayout buttonRow = new LinearLayout(this);
        buttonRow.setOrientation(LinearLayout.HORIZONTAL);
        Button connectButton = new Button(this);
        connectButton.setText("Tải người");
        Button startButton = new Button(this);
        startButton.setText("Xác thực");
        Button stopButton = new Button(this);
        stopButton.setText("Dừng");
        buttonRow.addView(connectButton, weightWrap());
        buttonRow.addView(startButton, weightWrap());
        buttonRow.addView(stopButton, weightWrap());
        root.addView(buttonRow);

        peopleSpinner = new Spinner(this);
        peopleSpinner.setAdapter(new ArrayAdapter<>(
                this,
                android.R.layout.simple_spinner_dropdown_item,
                people
        ));
        root.addView(label("Chọn người cần xác thực"));
        root.addView(peopleSpinner, matchWrap());

        previewView = new PreviewView(this);
        previewView.setImplementationMode(PreviewView.ImplementationMode.COMPATIBLE);
        previewView.setScaleType(PreviewView.ScaleType.FILL_CENTER);
        root.addView(previewView, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(300)
        ));

        statusText = label("Status: idle");
        challengeText = label("Challenge: waiting");
        scoreText = label("Scores: waiting");

        ScrollView scrollView = new ScrollView(this);
        LinearLayout resultBox = new LinearLayout(this);
        resultBox.setOrientation(LinearLayout.VERTICAL);
        resultBox.addView(statusText);
        resultBox.addView(challengeText);
        resultBox.addView(scoreText);
        scrollView.addView(resultBox);
        root.addView(scrollView, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1
        ));

        connectButton.setOnClickListener(v -> fetchPeople());
        startButton.setOnClickListener(v -> startSession());
        stopButton.setOnClickListener(v -> stopStreaming());
        setContentView(root);
    }

    private TextView label(String text) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(16);
        view.setGravity(Gravity.START);
        view.setPadding(0, 8, 0, 8);
        return view;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
        );
    }

    private LinearLayout.LayoutParams weightWrap() {
        return new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1);
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private String captureServerUrl() {
        String serverUrl = normalizeServerUrl(serverUrlInput.getText().toString());
        if (serverUrl.isEmpty()) {
            throw new IllegalArgumentException("Hãy nhập URL API.");
        }
        if (!serverUrl.startsWith("http://") && !serverUrl.startsWith("https://")) {
            throw new IllegalArgumentException("URL API phải bắt đầu bằng http:// hoặc https://");
        }
        getSharedPreferences("face_auth", MODE_PRIVATE)
                .edit()
                .putString("server_url", serverUrl)
                .apply();
        return serverUrl;
    }

    private String captureApiKey() {
        String apiKey = apiKeyInput.getText().toString().trim();
        if (apiKey.isEmpty()) {
            throw new IllegalArgumentException("Hãy nhập mã truy cập API.");
        }
        return apiKey;
    }

    private String normalizeServerUrl(String value) {
        value = value == null ? "" : value.trim();
        while (value.endsWith("/")) {
            value = value.substring(0, value.length() - 1);
        }
        return value;
    }

    private void fetchPeople() {
        final String server;
        final String apiKey;
        try {
            server = captureServerUrl();
            apiKey = captureApiKey();
        } catch (IllegalArgumentException exc) {
            setStatus(exc.getMessage());
            return;
        }
        setStatus("Đang lấy danh sách người từ API máy tính...");
        networkExecutor.execute(() -> {
            try {
                String response = httpGet(server + "/api/v1/identities", apiKey, null);
                JSONArray array = new JSONObject(response).getJSONArray("identities");
                List<String> loaded = new ArrayList<>();
                for (int i = 0; i < array.length(); i++) {
                    loaded.add(array.getString(i));
                }
                runOnUiThread(() -> {
                    people.clear();
                    people.addAll(loaded);
                    ((ArrayAdapter<?>) peopleSpinner.getAdapter()).notifyDataSetChanged();
                    setStatus("Đã tải danh sách. Chọn người rồi bấm Xác thực: " + loaded);
                });
            } catch (Exception exc) {
                setStatus("Không tải được danh sách từ PC: " + exc.getMessage());
            }
        });
    }

    private void startSession() {
        if (people.isEmpty()) {
            setStatus("Chưa có danh sách người. Bấm Tải người trước.");
            return;
        }
        final String server;
        final String apiKey;
        try {
            server = captureServerUrl();
            apiKey = captureApiKey();
        } catch (IllegalArgumentException exc) {
            setStatus(exc.getMessage());
            return;
        }
        String target = String.valueOf(peopleSpinner.getSelectedItem());
        long operationId = sessionOperations.begin();
        SessionContext previousSession;
        synchronized (sessionStateLock) {
            previousSession = activeSession;
            activeSession = null;
            streaming = false;
            if (previousSession != null) {
                previousSession.cancelled.set(true);
            }
        }
        setStatus("Đang tạo phiên xác thực cho: " + target);
        networkExecutor.execute(() -> {
            try {
                if (previousSession != null) {
                    deleteSessionBestEffort(previousSession);
                }
                if (destroyed || !sessionOperations.isCurrent(operationId)) {
                    return;
                }
                JSONObject request = new JSONObject();
                request.put("target_name", target);
                request.put("skip_liveness", false);
                String response = httpPostJson(
                        server + "/api/v1/sessions",
                        request.toString(),
                        apiKey
                );
                JSONObject json = new JSONObject(response);
                SessionContext createdSession = new SessionContext(
                        operationId,
                        server,
                        apiKey,
                        json.getString("session_id"),
                        json.getString("session_token")
                );
                boolean accepted;
                synchronized (sessionStateLock) {
                    accepted = !destroyed && sessionOperations.isCurrent(operationId);
                    if (accepted) {
                        activeSession = createdSession;
                        streaming = true;
                    }
                }
                if (!accepted) {
                    createdSession.cancelled.set(true);
                    deleteSessionBestEffort(createdSession);
                    return;
                }
                renderResult(json);
                setStatus("Đã bắt đầu xác thực cho: " + target);
            } catch (Exception exc) {
                if (!destroyed && sessionOperations.isCurrent(operationId)) {
                    setStatus("Không tạo được phiên xác thực: " + exc.getMessage());
                }
            }
        });
    }

    private void stopStreaming() {
        sessionOperations.cancel();
        SessionContext stoppedSession = detachActiveSession();
        setStatus("Đã dừng.");
        if (stoppedSession != null) {
            queueSessionDelete(stoppedSession);
        }
    }

    private SessionContext detachActiveSession() {
        synchronized (sessionStateLock) {
            SessionContext session = activeSession;
            activeSession = null;
            streaming = false;
            if (session != null) {
                session.cancelled.set(true);
            }
            return session;
        }
    }

    private boolean detachSessionIfActive(SessionContext session) {
        synchronized (sessionStateLock) {
            if (activeSession != session) {
                return false;
            }
            activeSession = null;
            streaming = false;
            session.cancelled.set(true);
            sessionOperations.cancelIfCurrent(session.operationId);
            return true;
        }
    }

    private boolean isActiveSession(SessionContext session) {
        return !destroyed
                && session != null
                && !session.cancelled.get()
                && activeSession == session
                && sessionOperations.isCurrent(session.operationId);
    }

    private void queueSessionDelete(SessionContext session) {
        if (networkExecutor.isShutdown()) {
            return;
        }
        networkExecutor.execute(() -> deleteSessionBestEffort(session));
    }

    private void deleteSessionBestEffort(SessionContext session) {
        try {
            httpDelete(
                    session.serverUrl + "/api/v1/sessions/" + session.sessionId,
                    session.apiKey,
                    session.sessionToken
            );
        } catch (Exception ignored) {
            // Session TTL remains the final cleanup fallback if the device is offline.
        }
    }

    private void setStatus(String text) {
        runOnUiThread(() -> statusText.setText("Status: " + text));
    }

    private void renderResult(JSONObject json) {
        runOnUiThread(() -> {
            try {
                JSONObject finalObj = json.optJSONObject("final");
                JSONObject liveness = json.optJSONObject("liveness");
                JSONObject detection = json.optJSONObject("detection");
                JSONObject recog = json.optJSONObject("recognition");
                JSONObject performance = json.optJSONObject("performance");
                String frameOrientation = json.optString("frame_orientation", "original");

                String finalStatus = finalObj == null ? "RUNNING" : finalObj.optString("status", "RUNNING");
                String finalCode = finalObj == null ? "IN_PROGRESS" : finalObj.optString("code", "IN_PROGRESS");
                String finalMessage = finalObj == null ? "" : finalObj.optString("message", "");
                int faceCount = detection == null ? 0 : detection.optInt("face_count", 0);
                int collectedSamples = performance == null ? 0 : performance.optInt("collected_samples", 0);
                String identityPrecheckStatus = performance == null
                        ? "waiting"
                        : performance.optString("identity_precheck_status", "waiting");
                JSONObject face = detection == null ? null : detection.optJSONObject("face");
                String detectionMessage = "";
                if (detection != null) {
                    JSONArray messages = detection.optJSONArray("messages");
                    if (messages != null && messages.length() > 0) {
                        detectionMessage = "\nMessage: " + messages.optString(0, "");
                    }
                }

                String instruction = liveness == null
                        ? "waiting"
                        : liveness.optString("current_instruction", "waiting");
                double timeLeft = liveness == null ? 0.0 : liveness.optDouble("time_left_seconds", 0.0);
                boolean livePass = liveness != null && liveness.optBoolean("passed", false);

                challengeText.setText(String.format(
                        Locale.US,
                        "Challenge: %s\nTime left: %.1fs | Active pass: %s\nFaces: %d | Samples: %d | Orientation: %s%s%s",
                        instruction,
                        timeLeft,
                        livePass,
                        faceCount,
                        collectedSamples,
                        frameOrientation,
                        detectionMessage,
                        face == null ? "" : String.format(
                                Locale.US,
                                "\nYaw/Pitch/Roll: %.1f / %.1f / %.1f\nBrightness: %.1f | Mouth: %.3f | Smile: %.3f",
                                face.optDouble("yaw", 0.0),
                                face.optDouble("pitch", 0.0),
                                face.optDouble("roll", 0.0),
                                face.optDouble("brightness", 0.0),
                                face.optDouble("mouth_open_score", 0.0),
                                face.optDouble("smile_score", 0.0)
                        )
                ));

                String recogText;
                if ("retrying".equals(identityPrecheckStatus)) {
                    recogText = "Recognition: retrying with all good frames";
                } else if ("ready".equals(identityPrecheckStatus)) {
                    recogText = "Recognition: ready; waiting for liveness";
                } else if ("running".equals(identityPrecheckStatus)) {
                    recogText = "Recognition: processing in background";
                } else {
                    recogText = "Recognition: waiting for 3 good frames";
                }
                if (recog != null) {
                    recogText = String.format(
                            Locale.US,
                            "Recognition: %s | Median %.1f%% | frames %d/%d | pass %s",
                            recog.optString("best_match_name", "UNKNOWN"),
                            recog.optDouble("similarity_percent", 0.0),
                            recog.optInt("passed_count", 0),
                            recog.optInt("sample_count", 0),
                            recog.optBoolean("is_recognized", false)
                    );
                }

                String renderedFinal = finalMessage.startsWith(finalStatus)
                        ? finalMessage
                        : finalStatus + (finalMessage.isEmpty() ? "" : " " + finalMessage);
                scoreText.setText(recogText + "\nFinal [" + finalCode + "]: " + renderedFinal);
            } catch (Exception exc) {
                statusText.setText("Status: render error " + exc.getMessage());
            }
        });
    }

    private void startCamera() {
        ListenableFuture<ProcessCameraProvider> providerFuture = ProcessCameraProvider.getInstance(this);
        providerFuture.addListener(() -> {
            try {
                cameraProvider = providerFuture.get();
                bindCameraUseCases();
            } catch (Exception exc) {
                setStatus("CameraX error: " + exc.getMessage());
            }
        }, ContextCompat.getMainExecutor(this));
    }

    private void bindCameraUseCases() {
        if (cameraProvider == null || previewView == null) {
            return;
        }
        Preview preview = new Preview.Builder().build();
        preview.setSurfaceProvider(previewView.getSurfaceProvider());

        ImageAnalysis imageAnalysis = new ImageAnalysis.Builder()
                .setResolutionSelector(
                        new ResolutionSelector.Builder()
                                .setResolutionStrategy(
                                        new ResolutionStrategy(
                                                new Size(640, 480),
                                                ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
                                        )
                                )
                                .build()
                )
                // RGBA has one documented byte layout on both real devices and
                // emulators, unlike YUV chroma planes which may be interleaved.
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build();
        imageAnalysis.setAnalyzer(cameraExecutor, this::analyzeImage);

        cameraProvider.unbindAll();
        cameraProvider.bindToLifecycle(
                this,
                CameraSelector.DEFAULT_FRONT_CAMERA,
                preview,
                imageAnalysis
        );
        setStatus("CameraX sẵn sàng. Tải người, chọn người rồi bấm Xác thực.");
    }

    private void analyzeImage(@NonNull ImageProxy image) {
        boolean reserved = false;
        SessionContext currentSession = activeSession;
        try {
            long now = System.currentTimeMillis();
            if (!streaming
                    || !isActiveSession(currentSession)
                    || now - currentSession.lastFrameSentAt < currentSession.frameIntervalMs) {
                return;
            }
            if (!currentSession.sendingFrame.compareAndSet(false, true)) {
                return;
            }
            reserved = true;
            currentSession.lastFrameSentAt = now;

            byte[] jpeg = rgbaImageProxyToJpeg(image);
            int rotationDegrees = image.getImageInfo().getRotationDegrees();
            networkExecutor.execute(() -> sendFrame(
                    currentSession,
                    jpeg,
                    rotationDegrees
            ));
        } catch (Exception exc) {
            if (reserved && currentSession != null) {
                currentSession.sendingFrame.set(false);
            }
            if (isActiveSession(currentSession)) {
                setStatus("Camera frame error: " + exc.getMessage());
            }
        } finally {
            image.close();
        }
    }

    private void sendFrame(
            SessionContext currentSession,
            byte[] jpeg,
            int rotationDegrees
    ) {
        try {
            if (!isActiveSession(currentSession)) {
                return;
            }
            String response = httpPostMultipart(
                    currentSession.serverUrl
                            + "/api/v1/sessions/"
                            + currentSession.sessionId
                            + "/frames",
                    jpeg,
                    rotationDegrees,
                    currentSession.apiKey,
                    currentSession.sessionToken
            );
            JSONObject json = new JSONObject(response);
            if (!isActiveSession(currentSession)) {
                return;
            }
            currentSession.frameIntervalMs = Math.max(
                    MIN_FRAME_INTERVAL_MS,
                    currentSession.frameIntervalMs - 50L
            );
            renderResult(json);
            String stage = json.optString("stage", "LIVENESS");
            if ("VERIFYING".equals(stage)) {
                synchronized (sessionStateLock) {
                    if (activeSession == currentSession) {
                        streaming = false;
                    }
                }
                pollVerification(currentSession);
            } else if ("SUCCESS".equals(stage) || "FAILED".equals(stage)) {
                synchronized (sessionStateLock) {
                    if (activeSession == currentSession) {
                        streaming = false;
                    }
                }
            }
        } catch (Exception exc) {
            if (!isActiveSession(currentSession)) {
                return;
            }
            String message = String.valueOf(exc.getMessage());
            if (message.startsWith("HTTP 429")) {
                currentSession.frameIntervalMs = Math.min(
                        MAX_FRAME_INTERVAL_MS,
                        Math.max(
                                MIN_FRAME_INTERVAL_MS + 100L,
                                currentSession.frameIntervalMs * 2L
                        )
                );
                setStatus(
                        "Server busy, automatically retrying more slowly ("
                                + currentSession.frameIntervalMs
                                + " ms)"
                );
            } else if (message.startsWith("HTTP 404") || message.startsWith("HTTP 410")) {
                if (detachSessionIfActive(currentSession)) {
                    setStatus("Phiên đã hết hạn. Bấm Xác thực để tạo phiên mới.");
                }
            } else {
                setStatus("Frame upload failed: " + message);
            }
        } finally {
            currentSession.sendingFrame.set(false);
        }
    }

    private byte[] rgbaImageProxyToJpeg(ImageProxy image) throws Exception {
        Bitmap bitmap = image.toBitmap();
        ByteArrayOutputStream jpeg = new ByteArrayOutputStream();
        if (!bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, jpeg)) {
            throw new IllegalStateException("Cannot encode camera frame as JPEG");
        }
        bitmap.recycle();
        return jpeg.toByteArray();
    }

    private void pollVerification(SessionContext currentSession) {
        if (!currentSession.pollingVerification.compareAndSet(false, true)) {
            return;
        }
        pollingExecutor.execute(() -> {
            long deadline = System.currentTimeMillis() + VERIFY_TIMEOUT_MS;
            long pollDelayMs = VERIFY_POLL_INTERVAL_MS;
            try {
                while (isActiveSession(currentSession)) {
                    if (System.currentTimeMillis() >= deadline) {
                        if (detachSessionIfActive(currentSession)) {
                            queueSessionDelete(currentSession);
                            runOnUiThread(() -> scoreText.setText(
                                    "Recognition: timeout\nFinal: FAILED: xác minh quá 60 giây"
                            ));
                            setStatus("Xác minh quá thời gian. Bấm Xác thực để thử lại.");
                        }
                        break;
                    }
                    try {
                        JSONObject json = new JSONObject(httpGet(
                                currentSession.serverUrl
                                        + "/api/v1/sessions/"
                                        + currentSession.sessionId,
                                currentSession.apiKey,
                                currentSession.sessionToken
                        ));
                        if (!isActiveSession(currentSession)) {
                            break;
                        }
                        renderResult(json);
                        pollDelayMs = VERIFY_POLL_INTERVAL_MS;
                        String stage = json.optString("stage", "VERIFYING");
                        if ("SUCCESS".equals(stage) || "FAILED".equals(stage)) {
                            break;
                        }
                    } catch (Exception pollError) {
                        if (!isActiveSession(currentSession)) {
                            break;
                        }
                        String message = String.valueOf(pollError.getMessage());
                        if (message.startsWith("HTTP 404") || message.startsWith("HTTP 410")) {
                            expireCurrentSession(currentSession);
                            break;
                        }
                        if (message.startsWith("HTTP 400")
                                || message.startsWith("HTTP 401")
                                || message.startsWith("HTTP 403")) {
                            if (detachSessionIfActive(currentSession)) {
                                setStatus("Không thể tiếp tục xác minh: " + message);
                            }
                            break;
                        }
                        setStatus(
                                "Mạng hoặc server đang chậm, tự thử lại sau "
                                        + pollDelayMs
                                        + " ms"
                        );
                        pollDelayMs = Math.min(
                                VERIFY_POLL_MAX_BACKOFF_MS,
                                Math.max(VERIFY_POLL_INTERVAL_MS, pollDelayMs * 2L)
                        );
                    }
                    Thread.sleep(pollDelayMs);
                }
            } catch (InterruptedException interrupted) {
                Thread.currentThread().interrupt();
            } catch (Exception exc) {
                if (!isActiveSession(currentSession)) {
                    return;
                }
                String message = String.valueOf(exc.getMessage());
                if (message.startsWith("HTTP 404") || message.startsWith("HTTP 410")) {
                    expireCurrentSession(currentSession);
                } else {
                    setStatus("Verification polling failed: " + message);
                }
            } finally {
                currentSession.pollingVerification.set(false);
            }
        });
    }

    private void expireCurrentSession(SessionContext currentSession) {
        if (!detachSessionIfActive(currentSession)) {
            return;
        }
        runOnUiThread(() -> scoreText.setText(
                "Recognition: waiting\nFinal: SESSION_EXPIRED"
        ));
        setStatus("Phiên không còn trên server. Bấm Xác thực để tạo phiên mới.");
    }

    private String httpGet(String urlString, String apiKey, String token) throws Exception {
        HttpURLConnection conn = (HttpURLConnection) new URL(urlString).openConnection();
        conn.setConnectTimeout(8000);
        conn.setReadTimeout(60000);
        conn.setRequestMethod("GET");
        applyAuthHeaders(conn, apiKey, token);
        return readResponse(conn);
    }

    private String httpPostJson(String urlString, String json, String apiKey) throws Exception {
        HttpURLConnection conn = (HttpURLConnection) new URL(urlString).openConnection();
        conn.setConnectTimeout(8000);
        conn.setReadTimeout(60000);
        conn.setRequestMethod("POST");
        conn.setDoOutput(true);
        conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8");
        applyAuthHeaders(conn, apiKey, null);
        byte[] body = json.getBytes(StandardCharsets.UTF_8);
        conn.setFixedLengthStreamingMode(body.length);
        try (DataOutputStream out = new DataOutputStream(conn.getOutputStream())) {
            out.write(body);
        }
        return readResponse(conn);
    }

    private String httpPostMultipart(
            String urlString,
            byte[] jpeg,
            int rotationDegrees,
            String apiKey,
            String token
    ) throws Exception {
        String boundary = "FaceAuthBoundary" + System.currentTimeMillis();
        HttpURLConnection conn = (HttpURLConnection) new URL(urlString).openConnection();
        conn.setConnectTimeout(8000);
        conn.setReadTimeout(60000);
        conn.setRequestMethod("POST");
        conn.setDoOutput(true);
        conn.setRequestProperty("Content-Type", "multipart/form-data; boundary=" + boundary);
        applyAuthHeaders(conn, apiKey, token);

        try (DataOutputStream out = new DataOutputStream(conn.getOutputStream())) {
            writeFormField(out, boundary, "mirror", "true");
            writeFormField(out, boundary, "rotation_degrees", String.valueOf(rotationDegrees));
            out.writeBytes("--" + boundary + "\r\n");
            out.writeBytes("Content-Disposition: form-data; name=\"image\"; filename=\"frame.jpg\"\r\n");
            out.writeBytes("Content-Type: image/jpeg\r\n\r\n");
            out.write(jpeg);
            out.writeBytes("\r\n--" + boundary + "--\r\n");
        }
        return readResponse(conn);
    }

    private String httpDelete(String urlString, String apiKey, String token) throws Exception {
        HttpURLConnection conn = (HttpURLConnection) new URL(urlString).openConnection();
        conn.setConnectTimeout(8000);
        conn.setReadTimeout(10000);
        conn.setRequestMethod("DELETE");
        applyAuthHeaders(conn, apiKey, token);
        return readResponse(conn);
    }

    private void applyAuthHeaders(HttpURLConnection conn, String apiKey, String token) {
        if (apiKey != null && !apiKey.isEmpty()) {
            conn.setRequestProperty("X-API-Key", apiKey);
        }
        if (token != null && !token.isEmpty()) {
            conn.setRequestProperty("X-Session-Token", token);
        }
    }

    private void writeFormField(
            DataOutputStream out,
            String boundary,
            String name,
            String value
    ) throws Exception {
        out.writeBytes("--" + boundary + "\r\n");
        out.writeBytes("Content-Disposition: form-data; name=\"" + name + "\"\r\n\r\n");
        out.writeBytes(value + "\r\n");
    }

    private String readResponse(HttpURLConnection conn) throws Exception {
        int code = conn.getResponseCode();
        InputStream input = code >= 200 && code < 300 ? conn.getInputStream() : conn.getErrorStream();
        StringBuilder builder = new StringBuilder();
        if (input != null) {
            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(input, StandardCharsets.UTF_8)
            )) {
                String line;
                while ((line = reader.readLine()) != null) {
                    builder.append(line);
                }
            }
        }
        conn.disconnect();
        if (code < 200 || code >= 300) {
            throw new RuntimeException("HTTP " + code + ": " + builder);
        }
        return builder.toString();
    }

    @Override
    protected void onDestroy() {
        destroyed = true;
        sessionOperations.cancel();
        SessionContext session = detachActiveSession();
        if (session != null) {
            queueSessionDelete(session);
        }
        if (cameraProvider != null) {
            cameraProvider.unbindAll();
        }
        cameraExecutor.shutdownNow();
        pollingExecutor.shutdownNow();
        // Let an in-flight create finish so it can delete any orphaned server
        // session, and let the best-effort DELETE queued above run.
        networkExecutor.shutdown();
        super.onDestroy();
    }
}
