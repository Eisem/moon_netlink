# Reproducible protocol robustness

```sh
bash .ci/validate-robustness.sh
```

The Linux wrapper limits each package's build/test process to 120 seconds and
kills the process group after a further five seconds. A timeout, panic or
unexpected outcome fails the command. These pure tests also run in the ordinary
Windows native test suite; the wrapper requires GNU `timeout`.

| Seed (xorshift32) | Fixed budget | Assertions |
| --- | --- | --- |
| `0x4d4e4c31` | 512 chains, 1–16 attributes, payloads up to 31 bytes | Shuffled unknown attribute types, flags and nested child data survive encoding/decoding without changing order or payload |
| `0x4d4e4c32` | 512 messages/attributes, payloads 1–128 bytes | Generated truncations and lengths below header size, beyond available input and above signed range produce their structured codec errors |
| `0x4d4e4c33` | 256 typed Link messages | Reordering name/MTU/kind and unknown attributes preserves the typed values; malformed nested child lengths are rejected |

There are no external randomness sources, network privileges or kernel writes.
Failures identify the fixed seed and iteration. Reproduce a failure with the
same test and seed, reduce its attribute list/payload while preserving the
error, and add the resulting wire bytes as a focused regression fixture before
changing the parser. The current run found no failing generated input, so no
new failure fixture is claimed.

This bounded deterministic corpus supplements the hand-written malformed-input
fixtures. It is not an exhaustive fuzzing or proof of safety for every byte
sequence. Kernel I/O, cancellation, protection and compensation are covered by
their separate transport/reconciliation and isolated integration tests.
