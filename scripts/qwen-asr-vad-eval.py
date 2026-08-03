#!/usr/bin/env python3
"""Reproducible live evaluation for Qwen run-task noise filtering and VAD.

The generated corpus contains only public synthetic phrases. The runner reads the
existing Responsay Qwen ASR credential from the environment or macOS Keychain,
keeps it in memory, and never writes it or request headers to the result file.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import pathlib
import platform
import shutil
import statistics
import subprocess
import sys
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Iterable


MODEL = "qwen-audio-3.0-asr-flash-streaming"
ENDPOINT = "wss://dashscope.aliyuncs.com/api-ws/v1/inference"
SAMPLE_RATE = 16_000
FRAME_BYTES = 3_200  # 100 ms, 16 kHz mono Int16
KEYCHAIN_SERVICE = "com.responsay.byok"
KEYCHAIN_ACCOUNT = "byok.qwen-asr-flash"

PROFILES: tuple[dict[str, Any], ...] = (
    {"id": "provider-defaults", "parameters": {}},
    {"id": "noise-threshold-minus-0.1", "parameters": {"speech_noise_threshold": -0.1}},
    {"id": "noise-threshold-0.0", "parameters": {"speech_noise_threshold": 0.0}},
    {"id": "noise-threshold-plus-0.1", "parameters": {"speech_noise_threshold": 0.1}},
    {"id": "multi-threshold", "parameters": {"multi_threshold_mode_enabled": True}},
    {"id": "semantic-segmentation", "parameters": {"semantic_punctuation_enabled": True}},
)


@dataclass(frozen=True)
class CorpusCase:
    case_id: str
    reference: str
    expected_segments: int
    categories: tuple[str, ...]
    matrix: bool = True

    def as_json(self) -> dict[str, Any]:
        return {
            "id": self.case_id,
            "reference": self.reference,
            "expected_segments": self.expected_segments,
            "categories": list(self.categories),
            "matrix": self.matrix,
            "pcm": f"{self.case_id}.pcm",
        }


CASES: tuple[CorpusCase, ...] = (
    CorpusCase(
        "normal-zh",
        "今天下午三点开会，请准备合同审查意见。",
        1,
        ("speech", "normal", "zh"),
    ),
    CorpusCase(
        "normal-en",
        "Please review the contract before the meeting this afternoon.",
        1,
        ("speech", "normal", "en"),
    ),
    CorpusCase(
        "mixed-zh-en",
        "请把 project release notes 发给 Daniel。",
        1,
        ("speech", "normal", "mixed"),
    ),
    CorpusCase(
        "quiet-zh",
        "请确认明天上午九点的会议安排。",
        1,
        ("speech", "quiet", "zh"),
    ),
    CorpusCase(
        "speech-with-noise",
        "背景有噪声时，也要准确记录这句话。",
        1,
        ("speech", "noise", "zh"),
    ),
    CorpusCase("noise-only", "", 0, ("noise",)),
    CorpusCase(
        "pause-segmentation",
        "第一段讨论合同范围。第二段确认交付日期。",
        2,
        ("speech", "pauses", "zh"),
    ),
    CorpusCase(
        "long-silence-keepalive",
        "静音之后连接仍然有效。",
        1,
        ("speech", "keepalive", "zh"),
        matrix=False,
    ),
)

CANONICAL_PCM_SHA256 = {
    "normal-zh": "668050a6024f8e79905ced1486ebc5c14f2d02337ec76c6a0f3cab08e9c692b2",
    "normal-en": "3a000346f5b2760b3a3fb0c01c3ddc9bcc0ee7636444af4e369f9d93ef9116c1",
    "mixed-zh-en": "e50f99275d8b733360073414deaad53c0c696e9f9b71edb3ece3de1599f2a52b",
    "quiet-zh": "e0606bfa22ab8f4de733b16d8071abfba4ea75accccf744fd3eaa38e1f6381c7",
    "speech-with-noise": "c211b3fc5556a763ed937ecdf44f8bbc3752c2cb6fa4eebcdcceb8dbabf6e998",
    "noise-only": "4e1093ceddbd093784b1d1edcfb62e0b4badeede015d0fcb0da6d99a9c94d618",
    "pause-segmentation": "feff5c5a4f25ec1b224038e6febafa2d770c0e6e2cbd5210c0c4d96d495ed5f9",
    "long-silence-keepalive": "dea03bffcc31b2a45def270f70de6afc0e0b978e055de016ee003a73c54e5983",
}


def run_command(argv: list[str]) -> None:
    subprocess.run(argv, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def require_command(name: str) -> str:
    path = shutil.which(name)
    if path is None:
        raise RuntimeError(f"required command is unavailable: {name}")
    return path


def synthesize(text: str, output: pathlib.Path, voice: str) -> None:
    say = require_command("say")
    ffmpeg = require_command("ffmpeg")
    intermediate = output.with_suffix(".aiff")
    run_command([say, "-v", voice, "-r", "175", "-o", str(intermediate), text])
    try:
        run_command([
            ffmpeg,
            "-y",
            "-i",
            str(intermediate),
            "-ac",
            "1",
            "-ar",
            str(SAMPLE_RATE),
            "-f",
            "s16le",
            str(output),
        ])
    finally:
        intermediate.unlink(missing_ok=True)


def transform_pcm(source: pathlib.Path, output: pathlib.Path, audio_filter: str) -> None:
    run_command([
        require_command("ffmpeg"),
        "-y",
        "-f",
        "s16le",
        "-ar",
        str(SAMPLE_RATE),
        "-ac",
        "1",
        "-i",
        str(source),
        "-af",
        audio_filter,
        "-f",
        "s16le",
        str(output),
    ])


def generate_corpus(output: pathlib.Path) -> None:
    if platform.system() != "Darwin":
        raise RuntimeError("corpus generation uses the macOS say command")
    output.mkdir(parents=True, exist_ok=True)
    zh_voice = "Flo (Chinese (China mainland))"
    en_voice = "Samantha"

    for case in CASES[:2]:
        synthesize(case.reference, output / f"{case.case_id}.pcm", en_voice if "en" in case.categories else zh_voice)

    mixed_parts = (
        ("请把", zh_voice),
        ("project release notes", en_voice),
        ("发给", zh_voice),
        ("Daniel", en_voice),
    )
    mixed_paths: list[pathlib.Path] = []
    for index, (text, voice) in enumerate(mixed_parts):
        part = output / f"mixed-part-{index}.pcm"
        synthesize(text, part, voice)
        mixed_paths.append(part)
    mixed_inputs: list[str] = []
    for path in mixed_paths:
        mixed_inputs.extend([
            "-f", "s16le", "-ar", str(SAMPLE_RATE), "-ac", "1", "-i", str(path),
        ])
    run_command([
        require_command("ffmpeg"),
        "-y",
        *mixed_inputs,
        "-filter_complex",
        "".join(f"[{index}:a]" for index in range(len(mixed_paths)))
        + f"concat=n={len(mixed_paths)}:v=0:a=1",
        "-f",
        "s16le",
        str(output / "mixed-zh-en.pcm"),
    ])
    for path in mixed_paths:
        path.unlink(missing_ok=True)

    quiet_source = output / "quiet-source.pcm"
    synthesize(CASES[3].reference, quiet_source, zh_voice)
    transform_pcm(quiet_source, output / "quiet-zh.pcm", "volume=0.08")
    quiet_source.unlink(missing_ok=True)

    noisy_source = output / "noisy-source.pcm"
    synthesize(CASES[4].reference, noisy_source, zh_voice)
    run_command([
        require_command("ffmpeg"),
        "-y",
        "-f",
        "s16le",
        "-ar",
        str(SAMPLE_RATE),
        "-ac",
        "1",
        "-i",
        str(noisy_source),
        "-f",
        "lavfi",
        "-i",
        "anoisesrc=color=pink:sample_rate=16000:amplitude=0.10:duration=20:seed=53",
        "-filter_complex",
        "[0:a]volume=0.70[s];[s][1:a]amix=inputs=2:duration=first:normalize=0",
        "-f",
        "s16le",
        str(output / "speech-with-noise.pcm"),
    ])
    noisy_source.unlink(missing_ok=True)

    run_command([
        require_command("ffmpeg"),
        "-y",
        "-f",
        "lavfi",
        "-i",
        "anoisesrc=color=pink:sample_rate=16000:amplitude=0.10:duration=4:seed=53",
        "-f",
        "s16le",
        str(output / "noise-only.pcm"),
    ])

    pause_first = output / "pause-first.pcm"
    pause_second = output / "pause-second.pcm"
    synthesize("第一段讨论合同范围。", pause_first, zh_voice)
    synthesize("第二段确认交付日期。", pause_second, zh_voice)
    run_command([
        require_command("ffmpeg"),
        "-y",
        "-f",
        "s16le",
        "-ar",
        str(SAMPLE_RATE),
        "-ac",
        "1",
        "-i",
        str(pause_first),
        "-f",
        "lavfi",
        "-i",
        "anullsrc=r=16000:cl=mono:d=1.6",
        "-f",
        "s16le",
        "-ar",
        str(SAMPLE_RATE),
        "-ac",
        "1",
        "-i",
        str(pause_second),
        "-filter_complex",
        "[0:a][1:a][2:a]concat=n=3:v=0:a=1",
        "-f",
        "s16le",
        str(output / "pause-segmentation.pcm"),
    ])
    pause_first.unlink(missing_ok=True)
    pause_second.unlink(missing_ok=True)

    keepalive_speech = output / "keepalive-speech.pcm"
    synthesize(CASES[-1].reference, keepalive_speech, zh_voice)
    run_command([
        require_command("ffmpeg"),
        "-y",
        "-f",
        "lavfi",
        "-i",
        "anullsrc=r=16000:cl=mono:d=61",
        "-f",
        "s16le",
        "-ar",
        str(SAMPLE_RATE),
        "-ac",
        "1",
        "-i",
        str(keepalive_speech),
        "-filter_complex",
        "[0:a][1:a]concat=n=2:v=0:a=1",
        "-f",
        "s16le",
        str(output / "long-silence-keepalive.pcm"),
    ])
    keepalive_speech.unlink(missing_ok=True)

    manifest_cases: list[dict[str, Any]] = []
    for case in CASES:
        case_json = case.as_json()
        actual_sha256 = hashlib.sha256((output / case_json["pcm"]).read_bytes()).hexdigest()
        expected_sha256 = CANONICAL_PCM_SHA256[case.case_id]
        if actual_sha256 != expected_sha256:
            raise RuntimeError(
                f"generated corpus differs from the evaluated canonical PCM: {case.case_id}"
            )
        case_json["sha256"] = actual_sha256
        manifest_cases.append(case_json)
    manifest = {
        "schema_version": 1,
        "audio": {"format": "pcm_s16le", "sample_rate": SAMPLE_RATE, "channels": 1},
        "generator": {
            "script": "scripts/qwen-asr-vad-eval.py",
            "voices": {"zh": zh_voice, "en": en_voice},
            "quiet_volume": 0.08,
            "noise_seed": 53,
        },
        "cases": manifest_cases,
    }
    (output / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps({"generated": str(output), "cases": len(CASES)}, ensure_ascii=False))


def read_api_key() -> str:
    from_environment = os.environ.get("DASHSCOPE_API_KEY", "").strip()
    if from_environment:
        return from_environment
    if platform.system() != "Darwin":
        raise RuntimeError("set DASHSCOPE_API_KEY outside macOS")
    result = subprocess.run(
        [
            "/usr/bin/security",
            "find-generic-password",
            "-s",
            KEYCHAIN_SERVICE,
            "-a",
            KEYCHAIN_ACCOUNT,
            "-w",
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0 or not result.stdout.strip():
        raise RuntimeError(f"Qwen ASR credential is unavailable in Keychain account {KEYCHAIN_ACCOUNT}")
    return result.stdout.strip()


def normalize_transcript(value: str) -> str:
    return "".join(character.lower() for character in value if character.isalnum())


def edit_distance(left: str, right: str) -> int:
    if len(left) > len(right):
        left, right = right, left
    previous = list(range(len(left) + 1))
    for right_index, right_character in enumerate(right, start=1):
        current = [right_index]
        for left_index, left_character in enumerate(left, start=1):
            current.append(min(
                current[-1] + 1,
                previous[left_index] + 1,
                previous[left_index - 1] + (left_character != right_character),
            ))
        previous = current
    return previous[-1]


def transcript_metrics(reference: str, transcript: str, expected_segments: int, segment_count: int) -> dict[str, Any]:
    normalized_reference = normalize_transcript(reference)
    normalized_transcript = normalize_transcript(transcript)
    is_speech = bool(normalized_reference)
    return {
        "cer": (
            edit_distance(normalized_reference, normalized_transcript) / len(normalized_reference)
            if is_speech else None
        ),
        "rejected": is_speech and not normalized_transcript,
        "noise_transcribed": not is_speech and bool(normalized_transcript),
        "transcript_characters": len(normalized_transcript),
        "segment_count": segment_count,
        "segmentation_error": abs(segment_count - expected_segments),
    }


def decode_message(raw: str | bytes) -> dict[str, Any]:
    if isinstance(raw, bytes):
        raw = raw.decode("utf-8", errors="replace")
    try:
        value = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return value if isinstance(value, dict) else {}


def receive_event(socket: Any) -> dict[str, Any]:
    return decode_message(socket.recv())


def event_name(message: dict[str, Any]) -> str:
    header = message.get("header")
    return str(header.get("event", "")) if isinstance(header, dict) else ""


def error_detail(message: dict[str, Any]) -> str:
    header = message.get("header")
    if not isinstance(header, dict):
        return "unknown provider error"
    code = str(header.get("error_code", "")).strip()
    detail = str(header.get("error_message", "")).strip()
    return ": ".join(part for part in (code, detail) if part) or "unknown provider error"


def sentence_from(message: dict[str, Any]) -> dict[str, Any] | None:
    try:
        sentence = message["payload"]["output"]["sentence"]
    except (KeyError, TypeError):
        return None
    if not isinstance(sentence, dict) or sentence.get("heartbeat") is True:
        return None
    return sentence


def drain_available(socket: Any, finals: dict[int, str], order: list[int]) -> None:
    import websocket

    socket.settimeout(0.001)
    try:
        while True:
            try:
                message = receive_event(socket)
            except websocket.WebSocketTimeoutException:
                return
            name = event_name(message)
            if name == "task-failed":
                raise RuntimeError(error_detail(message))
            sentence = sentence_from(message)
            if sentence is not None and sentence.get("sentence_end") is True:
                sentence_id = int(sentence.get("sentence_id", 0))
                if sentence_id not in finals:
                    order.append(sentence_id)
                finals[sentence_id] = str(sentence.get("text", ""))
    finally:
        socket.settimeout(30)


def run_trial(
    pcm: bytes,
    reference: str,
    expected_segments: int,
    parameters: dict[str, Any],
    api_key: str,
) -> dict[str, Any]:
    import websocket

    socket = websocket.create_connection(
        ENDPOINT,
        header=[f"Authorization: Bearer {api_key}"],
        timeout=30,
        enable_multithread=False,
    )
    task_id = str(uuid.uuid4())
    finals: dict[int, str] = {}
    order: list[int] = []
    started_at = time.monotonic()
    try:
        request_parameters: dict[str, Any] = {
            "format": "pcm",
            "sample_rate": SAMPLE_RATE,
            # This is the existing product keepalive behavior and is orthogonal to
            # the VAD/noise candidates under evaluation.
            "heartbeat": True,
        }
        request_parameters.update(parameters)
        socket.send(json.dumps({
            "header": {"action": "run-task", "task_id": task_id, "streaming": "duplex"},
            "payload": {
                "task_group": "audio",
                "task": "asr",
                "function": "recognition",
                "model": MODEL,
                "parameters": request_parameters,
                "input": {},
            },
        }, ensure_ascii=False))

        while True:
            message = receive_event(socket)
            name = event_name(message)
            if name == "task-started":
                break
            if name == "task-failed":
                raise RuntimeError(error_detail(message))

        for offset in range(0, len(pcm), FRAME_BYTES):
            frame_started = time.monotonic()
            socket.send_binary(pcm[offset : offset + FRAME_BYTES])
            drain_available(socket, finals, order)
            remaining = 0.1 - (time.monotonic() - frame_started)
            if remaining > 0:
                time.sleep(remaining)

        drain_available(socket, finals, order)
        finish_sent_at = time.monotonic()
        socket.settimeout(30)
        socket.send(json.dumps({
            "header": {"action": "finish-task", "task_id": task_id, "streaming": "duplex"},
            "payload": {"input": {}},
        }))
        while True:
            message = receive_event(socket)
            name = event_name(message)
            if name == "task-failed":
                raise RuntimeError(error_detail(message))
            sentence = sentence_from(message)
            if sentence is not None and sentence.get("sentence_end") is True:
                sentence_id = int(sentence.get("sentence_id", 0))
                if sentence_id not in finals:
                    order.append(sentence_id)
                finals[sentence_id] = str(sentence.get("text", ""))
            if name == "task-finished":
                finished_at = time.monotonic()
                break

        meaningful_order = [
            sentence_id for sentence_id in order if normalize_transcript(finals[sentence_id])
        ]
        transcript = "".join(finals[sentence_id] for sentence_id in meaningful_order)
        metrics = transcript_metrics(reference, transcript, expected_segments, len(meaningful_order))
        metrics.update({
            "release_latency_ms": round((finished_at - finish_sent_at) * 1000, 1),
            "wall_time_ms": round((finished_at - started_at) * 1000, 1),
        })
        return metrics
    finally:
        socket.close()


def load_manifest(corpus: pathlib.Path) -> dict[str, Any]:
    manifest_path = corpus / "manifest.json"
    value = json.loads(manifest_path.read_text(encoding="utf-8"))
    if value.get("schema_version") != 1:
        raise RuntimeError("unsupported corpus manifest schema")
    return value


def load_verified_audio(corpus: pathlib.Path, manifest: dict[str, Any]) -> dict[str, bytes]:
    audio: dict[str, bytes] = {}
    for case in manifest.get("cases", []):
        case_id = str(case.get("id", ""))
        pcm_name = str(case.get("pcm", ""))
        expected_sha256 = str(case.get("sha256", ""))
        if not case_id or not pcm_name or len(expected_sha256) != 64:
            raise RuntimeError("corpus manifest is missing a case id, PCM path, or SHA-256")
        pcm_path = (corpus / pcm_name).resolve()
        if not pcm_path.is_relative_to(corpus):
            raise RuntimeError(f"corpus PCM path escapes the corpus directory: {pcm_name}")
        pcm = pcm_path.read_bytes()
        actual_sha256 = hashlib.sha256(pcm).hexdigest()
        if actual_sha256 != expected_sha256:
            raise RuntimeError(f"corpus SHA-256 mismatch: {case_id}")
        audio[case_id] = pcm
    return audio


def evaluate(corpus: pathlib.Path, output: pathlib.Path, repeats: int) -> None:
    manifest = load_manifest(corpus)
    corpus = corpus.resolve()
    audio = load_verified_audio(corpus, manifest)
    api_key = read_api_key()
    trials: list[dict[str, Any]] = []
    matrix_cases = [case for case in manifest["cases"] if case.get("matrix", True)]
    total = len(PROFILES) * len(matrix_cases) * repeats + 1
    progress = 0
    for profile in PROFILES:
        for case in matrix_cases:
            pcm = audio[case["id"]]
            for repeat in range(1, repeats + 1):
                progress += 1
                print(
                    f"[{progress}/{total}] {profile['id']} {case['id']} repeat {repeat}",
                    file=sys.stderr,
                    flush=True,
                )
                metrics = run_trial(
                    pcm,
                    case["reference"],
                    int(case["expected_segments"]),
                    profile["parameters"],
                    api_key,
                )
                trials.append({
                    "profile": profile["id"],
                    "case": case["id"],
                    "categories": case["categories"],
                    "repeat": repeat,
                    **metrics,
                })

    keepalive = next(case for case in manifest["cases"] if not case.get("matrix", True))
    progress += 1
    print(f"[{progress}/{total}] provider-defaults {keepalive['id']} repeat 1", file=sys.stderr, flush=True)
    keepalive_metrics = run_trial(
        audio[keepalive["id"]],
        keepalive["reference"],
        int(keepalive["expected_segments"]),
        {},
        api_key,
    )
    trials.append({
        "profile": "provider-defaults",
        "case": keepalive["id"],
        "categories": keepalive["categories"],
        "repeat": 1,
        **keepalive_metrics,
    })

    result = {
        "schema_version": 1,
        "evaluated_at": datetime.now(timezone.utc).isoformat(),
        "model": MODEL,
        "endpoint_host": ENDPOINT.split("/")[2],
        "repeats": repeats,
        "profiles": list(PROFILES),
        "corpus_generator": manifest["generator"],
        "corpus_sha256": {
            case["id"]: case["sha256"] for case in manifest["cases"]
        },
        "trials": trials,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"results": str(output), "trials": len(trials)}, ensure_ascii=False))


def percentile(values: list[float], fraction: float) -> float:
    if not values:
        return math.nan
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def average(values: Iterable[float]) -> float:
    materialized = list(values)
    return statistics.fmean(materialized) if materialized else math.nan


def aggregate_profile(trials: list[dict[str, Any]]) -> dict[str, Any]:
    matrix = [trial for trial in trials if "keepalive" not in trial["categories"]]
    speech = [trial for trial in matrix if "speech" in trial["categories"]]
    normal = [trial for trial in speech if "normal" in trial["categories"]]
    quiet = [trial for trial in speech if "quiet" in trial["categories"]]
    noise_only = [trial for trial in matrix if trial["case"] == "noise-only"]
    pauses = [trial for trial in matrix if "pauses" in trial["categories"]]
    latencies = [float(trial["release_latency_ms"]) for trial in speech]
    return {
        "speech_cer": average(float(trial["cer"]) for trial in speech),
        "normal_cer": average(float(trial["cer"]) for trial in normal),
        "quiet_cer": average(float(trial["cer"]) for trial in quiet),
        "quiet_rejection_rate": average(1.0 if trial["rejected"] else 0.0 for trial in quiet),
        "noise_transcription_rate": average(
            1.0 if trial["noise_transcribed"] else 0.0 for trial in noise_only
        ),
        "pause_segmentation_error": average(float(trial["segmentation_error"]) for trial in pauses),
        "release_latency_p50_ms": percentile(latencies, 0.50),
        "release_latency_p95_ms": percentile(latencies, 0.95),
    }


def candidate_decision(baseline: dict[str, Any], candidate: dict[str, Any]) -> tuple[str, list[str]]:
    reasons: list[str] = []
    quiet_safe = (
        candidate["quiet_rejection_rate"] <= baseline["quiet_rejection_rate"]
        and candidate["quiet_cer"] <= baseline["quiet_cer"] + 0.02
    )
    speech_safe = candidate["speech_cer"] <= baseline["speech_cer"] + 0.01
    normal_safe = candidate["normal_cer"] <= baseline["normal_cer"] + 0.01
    segmentation_safe = candidate["pause_segmentation_error"] <= baseline["pause_segmentation_error"]
    latency_budget = baseline["release_latency_p95_ms"] + max(
        250.0, baseline["release_latency_p95_ms"] * 0.20
    )
    latency_safe = candidate["release_latency_p95_ms"] <= latency_budget

    accuracy_gain = baseline["speech_cer"] - candidate["speech_cer"] >= 0.02
    noise_gain = baseline["noise_transcription_rate"] - candidate["noise_transcription_rate"] >= 0.34
    segmentation_gain = (
        baseline["pause_segmentation_error"] - candidate["pause_segmentation_error"] >= 0.50
    )

    if not quiet_safe:
        reasons.append("quiet-speech guard failed")
    if not speech_safe:
        reasons.append("overall speech CER guard failed")
    if not normal_safe:
        reasons.append("normal-speech CER guard failed")
    if not segmentation_safe:
        reasons.append("segmentation guard failed")
    if not latency_safe:
        reasons.append("release-latency guard failed")
    if not (accuracy_gain or noise_gain or segmentation_gain):
        reasons.append("no material accuracy, noise, or segmentation gain")

    passed = quiet_safe and speech_safe and normal_safe and segmentation_safe and latency_safe and (
        accuracy_gain or noise_gain or segmentation_gain
    )
    return ("go" if passed else "no-go", reasons)


def score(results_path: pathlib.Path) -> dict[str, Any]:
    results = json.loads(results_path.read_text(encoding="utf-8"))
    by_profile: dict[str, list[dict[str, Any]]] = {}
    for trial in results["trials"]:
        by_profile.setdefault(trial["profile"], []).append(trial)
    aggregates = {
        profile: aggregate_profile(trials)
        for profile, trials in by_profile.items()
        if any("keepalive" not in trial["categories"] for trial in trials)
    }
    baseline = aggregates["provider-defaults"]
    decisions: dict[str, Any] = {}
    for profile, aggregate in aggregates.items():
        if profile == "provider-defaults":
            continue
        decision, reasons = candidate_decision(baseline, aggregate)
        decisions[profile] = {"decision": decision, "reasons": reasons}
    keepalive_trials = [
        trial for trial in results["trials"] if "keepalive" in trial["categories"]
    ]
    summary = {
        "model": results["model"],
        "evaluated_at": results["evaluated_at"],
        "repeats": results["repeats"],
        "aggregates": aggregates,
        "decisions": decisions,
        "keepalive": {
            "passed": bool(keepalive_trials)
            and not keepalive_trials[0]["rejected"]
            and keepalive_trials[0]["cer"] <= 0.20,
            "metrics": keepalive_trials[0] if keepalive_trials else None,
        },
        "overall_decision": (
            "go" if any(value["decision"] == "go" for value in decisions.values()) else "no-go"
        ),
    }
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    generate_parser = subparsers.add_parser("generate", help="generate the public synthetic corpus")
    generate_parser.add_argument("--output", type=pathlib.Path, required=True)

    run_parser = subparsers.add_parser("run", help="run the live provider matrix")
    run_parser.add_argument("--corpus", type=pathlib.Path, required=True)
    run_parser.add_argument("--output", type=pathlib.Path, required=True)
    run_parser.add_argument("--repeats", type=int, default=3)

    score_parser = subparsers.add_parser("score", help="score a completed live result file")
    score_parser.add_argument("--input", type=pathlib.Path, required=True)

    args = parser.parse_args()
    if args.command == "generate":
        generate_corpus(args.output.resolve())
    elif args.command == "run":
        if args.repeats < 1:
            parser.error("--repeats must be positive")
        evaluate(args.corpus.resolve(), args.output.resolve(), args.repeats)
    else:
        print(json.dumps(score(args.input.resolve()), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
