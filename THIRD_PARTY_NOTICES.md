# Third-party notices

Responsay depends on or downloads the following open-source projects. Their licenses apply to their respective code and binaries.

| Project | Use | License |
|---|---|---|
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | Global keyboard shortcuts | MIT |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | Application updates | Permissive; see the upstream `LICENSE` and bundled external notices |
| [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) | Offline speech recognition and synthesis | Apache-2.0 |
| [ONNX Runtime](https://github.com/microsoft/onnxruntime) | Local model runtime | MIT |
| [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR) | Optional local OCR | Apache-2.0 |
| [Orca notification sounds](https://github.com/stablyai/orca) | Interaction sound samples | MIT; full notice in `macOS/Resources/Sounds/NOTICE-orca-sounds.md` |

The `Vendor/` directory is intentionally absent from Git. `scripts/fetch-sherpa-onnx.sh` downloads pinned upstream release artifacts and verifies their SHA-256 digests before creating local xcframeworks.
