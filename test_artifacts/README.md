# Test Artifact Layout

`test_artifacts/` is for reproducible validation evidence, not general project documentation.
The directory is ignored by git except for this README.

## Standard Layout

- `test_artifacts/latest/`: latest reruns that are still being inspected right now.
- `test_artifacts/baselines/`: keep stable PASS evidence worth preserving for future comparison.
- `test_artifacts/investigations/`: active debugging evidence grouped by topic such as replay, animation, or transport.
- `test_artifacts/archive/`: older evidence kept only for reference.
- `test_artifacts/tmp/`: disposable reruns, scratch captures, and intermediate outputs.

## Retention Rules

- Keep one latest PASS directory per scenario in `latest/`.
- Keep one or two representative FAIL directories only when they explain a regression.
- Move durable comparison evidence into `baselines/`.
- Send scratch reruns, loose screenshots, and one-off debug captures to `tmp/`.
- Prune old FAIL and `tmp/` directories regularly with `scripts/cleanup_artifacts.sh`.

## Legacy Folders

Existing top-level artifact folders were left in place to avoid breaking paths already referenced by logs and runbooks.
New artifact-producing work should prefer the standard layout above.
