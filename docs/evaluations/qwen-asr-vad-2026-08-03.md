# Qwen streaming noise/VAD evaluation (2026-08-03)

## Decision

No candidate cleared the go/no-go gate. Responsay therefore keeps Qwen's provider defaults for
noise filtering and VAD segmentation and does not expose a product tuning control. The existing
`heartbeat=true` override remains because it is an independent long-silence keepalive requirement;
the live keepalive case below passed.

This decision applies to `qwen-audio-3.0-asr-flash-streaming` on the China endpoint and to the
synthetic corpus recorded here. It is not evidence that every microphone or acoustic environment
will behave the same way.

## Official baseline

The current Alibaba Cloud [run-task client-event reference](https://help.aliyun.com/en/model-studio/fun-asr-client-events)
documents the following behavior for Qwen-Audio-3.0-ASR-Flash-Streaming:

| Parameter | Official behavior/default used as the baseline |
| --- | --- |
| `semantic_punctuation_enabled` | `false`; VAD segmentation remains active |
| `max_sentence_silence` | `1300` ms |
| `multi_threshold_mode_enabled` | `false` |
| `speech_noise_threshold` | optional; no numeric default is published, so the baseline omits it |
| `heartbeat` | `false`; Responsay deliberately sends `true` to survive more than 60 seconds of silent audio |

The same reference warns that moving `speech_noise_threshold` toward `+1` can discard speech,
moving it toward `-1` can transcribe noise, and recommends testing changes in steps of `0.1`.

## Corpus and matrix

`scripts/qwen-asr-vad-eval.py generate` creates 16 kHz mono Int16 PCM with public phrases only.
The script uses the macOS system voices `Flo (Chinese (China mainland))` and `Samantha`, plus
seeded FFmpeg pink noise. It never reads user recordings, vocabulary, or transcript history.
The generated manifest records each PCM file's SHA-256 so reruns can verify corpus identity.

| Case | Coverage | Expected meaningful segments |
| --- | --- | ---: |
| `normal-zh` | normal Chinese speech | 1 |
| `normal-en` | normal English speech | 1 |
| `mixed-zh-en` | mixed Chinese-English speech | 1 |
| `quiet-zh` | quiet Chinese speech, peak about -27.4 dBFS | 1 |
| `speech-with-noise` | Chinese speech mixed with seeded pink noise | 1 |
| `noise-only` | seeded pink noise without speech | 0 |
| `pause-segmentation` | two Chinese clauses separated by 1.6 seconds | 2 |
| `long-silence-keepalive` | 61 seconds of silence followed by Chinese speech | 1 |

The three-repeat matrix compares provider defaults with `speech_noise_threshold` values `-0.1`,
`0.0`, and `+0.1`, `multi_threshold_mode_enabled=true`, and
`semantic_punctuation_enabled=true`. Every profile keeps `heartbeat=true`; the keepalive case runs
once on the otherwise-default profile.

The scorer marks a candidate `go` only if it:

- does not increase quiet-speech rejection and adds at most 0.02 quiet-speech CER;
- adds at most 0.01 overall and normal-speech CER;
- does not worsen the pause segmentation error;
- stays within 250 ms or 20% of baseline p95 release latency, whichever allowance is larger; and
- materially improves at least one target: 0.02 absolute speech CER, 0.34 noise false-positive
  rate, or 0.50 pause segmentation error.

## Reproduction

Prerequisites are macOS, `ffmpeg`, Python 3, and either the existing Responsay Keychain account
`byok.qwen-asr-flash` or `DASHSCOPE_API_KEY`. The dependency is installed into a disposable venv:

```bash
QWEN_EVAL_DIR=$(mktemp -d /tmp/responsay-qwen-asr-eval.XXXXXX)
python3 -m venv "$QWEN_EVAL_DIR/venv"
"$QWEN_EVAL_DIR/venv/bin/pip" install \
  -r scripts/qwen-asr-vad-eval-requirements.txt
"$QWEN_EVAL_DIR/venv/bin/python" scripts/qwen-asr-vad-eval.py generate \
  --output "$QWEN_EVAL_DIR/corpus"
"$QWEN_EVAL_DIR/venv/bin/python" scripts/qwen-asr-vad-eval.py run \
  --corpus "$QWEN_EVAL_DIR/corpus" \
  --output "$QWEN_EVAL_DIR/results.json" \
  --repeats 3
"$QWEN_EVAL_DIR/venv/bin/python" scripts/qwen-asr-vad-eval.py score \
  --input "$QWEN_EVAL_DIR/results.json"
```

The JSON result contains aggregate inputs and per-trial metrics, but not recognized text, API keys,
request headers, task IDs, user vocabulary, or private audio.

The live run used the following generated public corpus. The generator refuses output that differs
from these committed canonical hashes, and the runner refuses to make a provider call if a PCM
subsequently differs from the SHA-256 stored in its manifest.

| Case | Evaluated PCM SHA-256 |
| --- | --- |
| `normal-zh` | `668050a6024f8e79905ced1486ebc5c14f2d02337ec76c6a0f3cab08e9c692b2` |
| `normal-en` | `3a000346f5b2760b3a3fb0c01c3ddc9bcc0ee7636444af4e369f9d93ef9116c1` |
| `mixed-zh-en` | `e50f99275d8b733360073414deaad53c0c696e9f9b71edb3ece3de1599f2a52b` |
| `quiet-zh` | `e0606bfa22ab8f4de733b16d8071abfba4ea75accccf744fd3eaa38e1f6381c7` |
| `speech-with-noise` | `c211b3fc5556a763ed937ecdf44f8bbc3752c2cb6fa4eebcdcceb8dbabf6e998` |
| `noise-only` | `4e1093ceddbd093784b1d1edcfb62e0b4badeede015d0fcb0da6d99a9c94d618` |
| `pause-segmentation` | `feff5c5a4f25ec1b224038e6febafa2d770c0e6e2cbd5210c0c4d96d495ed5f9` |
| `long-silence-keepalive` | `dea03bffcc31b2a45def270f70de6afc0e0b978e055de016ee003a73c54e5983` |

## Live-provider result

Environment: macOS 26.5.2 (arm64), Python 3.14.5, FFmpeg 8.1.1, China generic endpoint,
`qwen-audio-3.0-asr-flash-streaming`. The run completed at 2026-08-03 07:12 UTC with 127
provider calls and no protocol, authentication, or timeout failures.

| Profile | Speech CER | Normal CER | Quiet CER | Quiet reject | Noise transcription | Pause error | Release p50 | Release p95 | Decision |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Provider defaults | 0.1003 | 0.0656 | 0.0714 | 0% | 0% | 0.00 | 356 ms | 735 ms | baseline |
| Noise threshold -0.1 | 0.1003 | 0.0656 | 0.0714 | 0% | 0% | 0.00 | 260 ms | 484 ms | no-go: no target gain |
| Noise threshold 0.0 | 0.1003 | 0.0656 | 0.0714 | 0% | 0% | 0.00 | 461 ms | 1103 ms | no-go: no target gain; latency guard |
| Noise threshold +0.1 | 0.1003 | 0.0656 | 0.0714 | 0% | 0% | 0.00 | 383 ms | 1190 ms | no-go: no target gain; latency guard |
| Multi-threshold | 0.1003 | 0.0656 | 0.0714 | 0% | 0% | 0.00 | 572 ms | 1846 ms | no-go: no target gain; latency guard |
| Semantic segmentation | 0.1003 | 0.0656 | 0.0714 | 0% | 0% | 0.00 | 432 ms | 1490 ms | no-go: no target gain; latency guard |

Recognition metrics were identical across all six profiles for every case. Provider defaults
already had zero quiet-speech rejection, zero noise-only transcription, and zero pause-segmentation
error, leaving no target improvement for a candidate to demonstrate. The `-0.1` profile had lower
observed release latency but did not improve any accuracy, noise, or segmentation target, so it
does not clear the predeclared gate. The other four candidates also exceeded the release-latency
guard in this run.

The independent keepalive trial streamed 61 seconds of silence before speech. It completed in
66.9 seconds wall time with CER 0, one meaningful segment, and 846 ms release latency. This is live
provider evidence that retaining `heartbeat=true` preserves the existing long-silence behavior.

## Live evidence versus deterministic validation

Live-provider evidence is limited to the parameter matrix and the long-silence case above. The
ordinary test suite does not contact Alibaba Cloud. Its deterministic coverage instead verifies
that product requests omit all four noise/VAD tuning fields, retain heartbeat, encode the run-task
envelope correctly, and ignore provider heartbeat frames when folding transcripts.

The synthetic live corpus is suitable for a bounded regression decision, not a claim about broad
real-world ASR quality. A future proposal should rerun this harness and add non-private,
representative microphone fixtures if it targets a newly observed acoustic failure.
