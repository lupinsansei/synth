# XS builds

When a change requires a new XS binary, run `perl native/build.pl` from the
repository root using the same Perl that runs the synth. This includes changes
to the native renderer or its build settings, a missing DLL, and a switch to
a different Perl version or architecture. Ordinary patch and GUI edits can
use the existing build.

Tell the user when you rebuild and whether it succeeded. If a running synth
has locked the DLL, ask the user to close it so you can retry.
