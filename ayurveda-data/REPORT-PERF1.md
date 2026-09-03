# PERF-1 — iPhone 15 Pro performance ceiling

Date: 2026-07-28

Branch: `ayurveda-app`

Required device: physical iPhone 15 Pro

## Outcome

**NOT RUN — required hardware unavailable.**

The only connected physical iPhone was:

| Device | Model | CoreDevice ID | State |
|---|---|---|---|
| Mincho's iPhone | iPhone 16 Pro (`iPhone17,1`) | `56F5A82A-D494-56E8-9C32-EA9307B45A04` | connected |

No iPhone 15 Pro was present. The other discovered phones were unavailable
iPhone 11 Pro or iPhone SE devices and cannot run this Apple Intelligence
feature.

Per the task packet, the connected iPhone 16 Pro and the simulator were not
used as substitutes. Therefore no signed Release run, ABAB series, or
provisional-ceiling verdict is reported.

## Required arms

| Arm | Required sample | Result |
|---|---:|---|
| Seven-day solve | monotonic timing, N ≥ 10 | **not run** |
| Role resolution cold | N ≥ 10 | **not run** |
| Role resolution cached | N ≥ 10 | **not run** |
| Cold launch | strict ABAB, N ≥ 10 per arm | **not run** |
| Peak memory | strict ABAB, N ≥ 10 per arm | **not run** |

No ceiling was exceeded because no measurement was taken. No optimization,
parameter change, or performance workaround was attempted.

## Resume condition

Repeat PERF-1 unchanged when a physical iPhone 15 Pro is connected:

- signed Release build;
- quiesced host;
- N ≥ 10;
- strict ABAB for launch and memory; and
- stop and report, without optimizing, if any provisional ceiling is
  exceeded.
