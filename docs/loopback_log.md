# Loopback Log

Use this file when validation fails or when implementation discovers that the current phase contract is wrong.

| Loopback ID | Req ID | Failed Evidence / Run | First Bad Transition | Classification | Return To Phase / Layer | Decision | Date | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `LB-TEMPLATE` | `<REQ-ID>` | `<artifact path>` | `<expected vs observed>` | contract wrong / probe wrong / stale environment / engine/API wrong / UI/bridge propagation wrong / transport/session wrong / device/environment contract wrong | `<phase or layer>` | `<what changes before next edit>` | `<date>` | Remove or keep as example when first real entry is added. |

## Loopback Rules

- Record the first failing transition, not just the final error.
- Do not patch a second layer until the failure is classified.
- If the same layer fails twice, stop and broaden diagnosis.
- If environment reset fixes the issue, classify it as stale environment unless artifacts prove a code fix.
- Link the RTM row and E2E evidence row whenever possible.
