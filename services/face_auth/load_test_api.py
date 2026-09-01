from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
import statistics
import time
from typing import Any

import requests


TERMINAL_STAGES = {"SUCCESS", "FAILED"}


@dataclass
class VirtualStudentResult:
    index: int
    stage: str
    result_code: str
    elapsed_seconds: float
    frame_requests: int
    overload_retries: int
    error: str = ""


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Bounded load test for concurrent Face Auth API sessions."
    )
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--target", required=True)
    parser.add_argument("--api-key", default="")
    parser.add_argument("--sessions", type=int, default=100)
    parser.add_argument("--concurrency", type=int, default=25)
    parser.add_argument("--frame-dir", type=Path, required=True)
    parser.add_argument("--frames-per-session", type=int, default=6)
    parser.add_argument("--frame-interval", type=float, default=0.25)
    parser.add_argument("--timeout-seconds", type=float, default=120.0)
    parser.add_argument(
        "--with-liveness",
        action="store_true",
        help="Use only with an ordered trace that can satisfy the random challenges.",
    )
    args = parser.parse_args()

    frame_paths = sorted(
        path
        for path in args.frame_dir.iterdir()
        if path.is_file() and path.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}
    )
    if not frame_paths:
        parser.error(f"No image frames found in {args.frame_dir}")
    frame_payloads = [(path.name, path.read_bytes()) for path in frame_paths]

    started = time.perf_counter()
    results: list[VirtualStudentResult] = []
    with ThreadPoolExecutor(max_workers=max(1, args.concurrency)) as executor:
        futures = [
            executor.submit(
                run_virtual_student,
                index,
                args.base_url.rstrip("/"),
                args.target,
                frame_payloads,
                max(1, args.frames_per_session),
                max(0.0, args.frame_interval),
                args.timeout_seconds,
                not args.with_liveness,
                args.api_key,
            )
            for index in range(max(1, args.sessions))
        ]
        for future in as_completed(futures):
            results.append(future.result())

    wall_seconds = time.perf_counter() - started
    successful_transport = [result for result in results if not result.error]
    elapsed = sorted(result.elapsed_seconds for result in successful_transport)
    stages: dict[str, int] = {}
    result_codes: dict[str, int] = {}
    for result in results:
        key = "ERROR" if result.error else result.stage
        stages[key] = stages.get(key, 0) + 1
        code = "TRANSPORT_ERROR" if result.error else (result.result_code or "UNKNOWN")
        result_codes[code] = result_codes.get(code, 0) + 1

    print(f"sessions={len(results)} concurrency={args.concurrency} wall={wall_seconds:.2f}s")
    print(f"stages={stages}")
    print(f"result_codes={result_codes}")
    print(f"overload_retries={sum(result.overload_retries for result in results)}")
    if elapsed:
        print(
            "latency_seconds "
            f"p50={percentile(elapsed, 50):.2f} "
            f"p95={percentile(elapsed, 95):.2f} "
            f"p99={percentile(elapsed, 99):.2f} "
            f"mean={statistics.fmean(elapsed):.2f}"
        )
    errors = [result for result in results if result.error]
    for result in errors[:10]:
        print(f"student={result.index} error={result.error}")
    return 1 if errors else 0


def run_virtual_student(
    index: int,
    base_url: str,
    target: str,
    frame_payloads: list[tuple[str, bytes]],
    frames_per_session: int,
    frame_interval: float,
    timeout_seconds: float,
    skip_liveness: bool,
    api_key: str,
) -> VirtualStudentResult:
    started = time.perf_counter()
    deadline = started + timeout_seconds
    frame_requests = 0
    overload_retries = 0
    session_id: str | None = None
    client = requests.Session()  # Preserves ALB affinity cookies per virtual phone.
    if api_key:
        client.headers["X-API-Key"] = api_key
    try:
        response = request_with_backoff(
            client,
            "POST",
            f"{base_url}/api/v1/sessions",
            deadline,
            json={"target_name": target, "skip_liveness": skip_liveness},
        )
        overload_retries += int(response.pop("_overload_retries", 0))
        session_id = str(response["session_id"])
        session_token = str(response["session_token"])
        client.headers["X-Session-Token"] = session_token
        stage = str(response.get("stage", "LIVENESS"))

        for frame_index in range(frames_per_session):
            if stage in TERMINAL_STAGES or stage == "VERIFYING":
                break
            name, payload = frame_payloads[frame_index % len(frame_payloads)]
            response = request_with_backoff(
                client,
                "POST",
                f"{base_url}/api/v1/sessions/{session_id}/frames",
                deadline,
                files={"image": (name, payload, "image/jpeg")},
                data={"mirror": "false", "rotation_degrees": "0"},
            )
            frame_requests += 1
            overload_retries += int(response.pop("_overload_retries", 0))
            stage = str(response.get("stage", "LIVENESS"))
            if frame_interval > 0 and stage not in TERMINAL_STAGES and stage != "VERIFYING":
                time.sleep(frame_interval)

        while stage not in TERMINAL_STAGES:
            if time.perf_counter() >= deadline:
                raise TimeoutError(f"session {session_id} did not finish before timeout")
            time.sleep(0.15)
            response = request_with_backoff(
                client,
                "GET",
                f"{base_url}/api/v1/sessions/{session_id}",
                deadline,
            )
            overload_retries += int(response.pop("_overload_retries", 0))
            stage = str(response.get("stage", "VERIFYING"))

        return VirtualStudentResult(
            index=index,
            stage=stage,
            result_code=str(
                response.get("final", {}).get(
                    "code", response.get("code", response.get("result_code", ""))
                )
            ),
            elapsed_seconds=time.perf_counter() - started,
            frame_requests=frame_requests,
            overload_retries=overload_retries,
        )
    except Exception as exc:
        return VirtualStudentResult(
            index=index,
            stage="ERROR",
            result_code="",
            elapsed_seconds=time.perf_counter() - started,
            frame_requests=frame_requests,
            overload_retries=overload_retries,
            error=str(exc),
        )
    finally:
        if session_id is not None:
            try:
                client.delete(
                    f"{base_url}/api/v1/sessions/{session_id}",
                    timeout=5.0,
                )
            except requests.RequestException:
                pass
        client.close()


def request_with_backoff(
    client: requests.Session,
    method: str,
    url: str,
    deadline: float,
    **kwargs: Any,
) -> dict[str, Any]:
    delay = 0.10
    overload_retries = 0
    while True:
        if time.perf_counter() >= deadline:
            raise TimeoutError(f"request timed out while waiting for capacity: {url}")
        response = client.request(method, url, timeout=15.0, **kwargs)
        if response.status_code != 429:
            response.raise_for_status()
            payload = response.json()
            payload["_overload_retries"] = overload_retries
            return payload
        overload_retries += 1
        time.sleep(delay)
        delay = min(2.0, delay * 1.8)


def percentile(sorted_values: list[float], value: float) -> float:
    if not sorted_values:
        return 0.0
    index = (len(sorted_values) - 1) * value / 100.0
    lower = int(index)
    upper = min(len(sorted_values) - 1, lower + 1)
    fraction = index - lower
    return sorted_values[lower] * (1.0 - fraction) + sorted_values[upper] * fraction


if __name__ == "__main__":
    raise SystemExit(main())
