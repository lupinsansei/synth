# XS builds

When a change requires a new XS binary, run `perl native/build.pl` from the
repository root using the same Perl that runs the synth. This includes changes
to the native renderer or its build settings, a missing DLL, and a switch to
a different Perl version or architecture. Ordinary patch and GUI edits can
use the existing build.

Tell the user when you rebuild and whether it succeeded. If a running synth
has locked the DLL, ask the user to close it so you can retry.

## Audio renderer changes

Prefer XS for sample-generating and mixing hot loops. Keep the Perl renderer
as a reference/fallback, and implement matching boundary behaviour in both.
For DSP changes, rebuild XS and run the native parity tests against the compiled
extension, comparing buffer lengths, samples, PCM and random-stream consumption.
CI must verify that XS actually loads before running native regressions; a
skipped optional-native test alone is not evidence of native correctness.
