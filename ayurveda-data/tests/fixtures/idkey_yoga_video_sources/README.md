# Yoga video lookup fixtures

The `144/` and `480/` JPEGs are deterministic reductions of the authored files
in `~/yoga-images`. They cover the requested physical frame indices and their
immediate neighbours, so the AVAssetImageGenerator regression test can prove
that UUID → frame index → integer CMTime returns the requested pose rather than
an adjacent pose at both shipped sizes.

Indices congruent to 1 modulo 3 are deliberately represented because they
reproduce the former decimal-seconds truncation defect.

The identity floors are intentionally per-variant: 0.85 for 144 after a
20-asana calibration measured 0.860546, and the food-equivalent 0.90 for 480
after measuring 0.920731. Heavy downscaling of Yoga's high-frequency
backgrounds makes 0.90 unreachable at 144. Both variants independently retain
the 0.10 minimum advantage over either neighbouring frame; that comparison is
the primary off-by-one detector.
