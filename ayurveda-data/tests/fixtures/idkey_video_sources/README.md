# ID-key video source fixtures

These are 144-pixel reference renders of the authored source images for the
physical frame numbers used by `test_idkey_video_lookup.py`. Neighboring frames
are included deliberately: the gate requires SSIM against the requested source
to be at least 0.90 and at least 0.10 higher than either neighbor.

The affected regression indices (`1, 4, 436, 472, 11194, 12514`) are all
congruent to 1 modulo 3. The former decimal-seconds lookup truncated each by one
600-Hz tick and returned its preceding fixture.
