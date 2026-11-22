# synth
Perl/TK synthesizer

*To Do*

- Speed it all up
- Add a button to the menu to restart
- Start/fork another instance and stop this one?
- Try and speed up sin() using memoize - not any quicker
- Maybe make a simple time this program to test the idea
- Also move any multiplications inside sin() into a new function that I can memoize
- Try memoizing the main function that generates sign waves too - not any quicker
- Try memoizing pack too - didn’t work but making pack operate on a whole list in mix samples, worked but added a click!
- Try PDL one day but that’s super complex
- Getting rid of lots of If statements helped
- Add an attack as well as decay. Stop generating samples and leave the loop when we have decayed to zero! We generate samples that are too long I reckon 
- Make this into a proper TK control stick it on cpan one day
- Randomise button
- Mutate button
- Take what decimal point should be
- Take how many digits to show 
- Generate every permutation of chopping up a sample. 24 permutations if we don’t repeat them
- With the synth maybe use the TK program to set the sounds but the console program to capture the keys? As console can do key up nicely.

Originally sponsored by [PICA](https://pica.org.au/)

## Super Spinbox

The oscillator/modulator frequency, volume, decay and delay controls now have a
`+` and `-` button for every digit. A digit changes its own decimal place with
normal carry/borrow: `9.9999` plus one ten-thousandth becomes `10.0000`.
Up always increases the numeric value, including when negative. Click the sign
to negate, or type a whole number in the entry below and press Enter/tab away.
Invalid text is highlighted and never sent to the synthesizer; Escape restores
the last value. Controls retain -1000..1000 limits except Delay, which uses 0..1000.
External voice changes refresh
the digits without triggering a second render.

Try the standalone, **silent** Tk demo (no Windows audio dependencies):

```sh
perl examples/super_spinbox.pl
```

Run the model and real Tk widget tests with Perl/Tk installed:

```sh
prove -Ilib t/super_spinbox.t
xvfb-run -a prove -Ilib t/super_spinbox_tk.t  # Linux/headless; use prove directly with a display
```

`lib/SuperSpinbox.pm` is reusable with a parent widget, scalar variable, decimal
places, bounds and change callback. `lib/SuperSpinbox/Value.pm` holds the testable
fixed-point stepping model. The full synthesizer still requires its original
Windows audio/MIDI/Moose dependencies; the demo does not play audio.


## Voice delay

**Delay** is a non-negative number of milliseconds (0..1000 in the GUI and
patch banks). It inserts stereo silence before a voice, rounding to the nearest
frame at the render sample rate. The existing render window is preserved: the
end is trimmed, and a delay at or beyond the window produces silence. WAV voices
with automatic duration retain the original file's frame count.

A modulator's delay postpones its modulation, not the carrier's sound. Nested
delays are relative to each parent's onset: delaying a parent shifts its entire
modulation subtree, including oscillator phase and voice decay. The patch's
attack/decay envelope still runs over the overall patch timeline, so it may
attenuate a late voice. This is separate from playback chord arpeggio spacing;
like other rendered settings, voice delay transposes with the rendered sample.
Negative or non-finite delays are rejected, including in imported banks.

Silent regression checks: `prove -I. -Ilib t/voice_delay.t`.

## Playback chord memory

Turn on **Chord memory** and choose Major, Minor, Major 7th, Minor 7th,
Dominant 7th, Sus2, Sus4 or Octave. Each keyboard note triggers the already-rendered
sample on independent playback channels: Major 7th uses 0, 4, 7 and 11 semitones.
Changing this setting does **not** regenerate or rewrite the patch. Release the
key to stop all its voices; changing presets while held does not change release
behaviour. The on-screen piano buttons play one-shot chords.

Choose **Together** (default) for all chord tones at once, or **Arpeggio** for
one ascending pass through the chord. **Arpeggio step (ms)** sets the spacing
from 40–1000 ms (default 120 ms); note tails can overlap. All voice buffers are
prepared before asynchronous playback is submitted, so slow channel setup no
longer sits between tone starts. Arpeggio timing is sample padding adjusted for
each voice's playback rate, not GUI sleeps. Releasing a key also cancels tones
whose silent lead-in has not finished. Changing mode affects the next key;
mode and spacing save with the patch bank. Short sequencer gates can cut an
arpeggio off before its higher tones; use Together or shorter spacing there.

The older sample-generation **Baked chord (legacy)** option remains available. Its
C3/E3/F3/A3 mix is referenced to C3, so played notes and octave shifts transpose
the entire baked chord from its root rather than its final rendered tone.
The GUI's default bass patch now starts with that option off, so playback chord
memory builds harmony from a single-note sample rather than stacking chords.
Other patches that already contain a chord will still transpose that whole chord.

Active voices get separate slots, growing as needed rather than wrapping over a
held note. Completed/released slots are reused. This is not literally unlimited
hardware polyphony: the Windows audio driver may impose its own device limits.
A partial chord failure releases the voices already started.

## Panic / All notes off

Click **Panic / All notes off** beside the chord controls to stop the sequencer
and silence every playback channel, including keyboard notes, one-shot piano
and explorer auditions, and arpeggio tones still in their silent lead-in.
Held-key bookkeeping is cleared so you can play again. The patch, chord settings
and sequencer pattern are unchanged; the sequencer stays stopped until Play.
If a device refuses to pause, the other channels are still attempted and an
error is shown. A failed channel is retained for another Panic attempt.

## Mini sequencer

**Randomise & Play** generates and immediately loops a new 16-step phrase.
Keep clicking until you hear something you like; **Play** repeats the current
phrase, **Stop** silences it. Tempo is 40–240 BPM with sixteenth-note steps.
The clock uses monotonic deadlines so playback setup and UI refresh do not add
to every step's duration. Fractional intervals are preserved; after a long stall,
timing restarts from the current callback rather than bursting through missed
notes. Actual audio-device latency is not compensated.
Choose a major, minor or minor-pentatonic scale for the next randomisation.
The numbered buttons show notes/rests; click to mute or restore a step's original
pitch. Clicking an original rest generates a note in the selected scale. Muting
and restoring does not reroll notes, even if the scale has changed. Randomising
starts a fresh phrase and forgets the old phrase's muted pitches.
Use **Octave - / Octave +** to set the sequencer's root C from octave 0–7,
independently of the computer keyboard. Changing octave updates the labels and
the next playing step without changing the pattern or restarting its clock.
This octave is session-only. Chord memory applies
to the sequencer too, using the current patch without regenerating it.

This is a small 303-inspired idea generator, not a 303 emulation: no accent,
slide, filter model, sequence save/load or audio export in this prototype.
A silent portable UI demo prints generated frequencies instead of playing audio:

```sh
perl examples/mini_sequencer.pl
```

All automated tests use real Tk widgets (under Xvfb on CI) and a fake WaveOut
backend for playback; they never access audio hardware. They cover stepping,
carry/borrow, typed/external edits, chord pitches, held-key release, device errors,
random-pattern bounds and the sequencer clock/stop/restart lifecycle. Windows
sound output and full synth GUI playback still need an on-device listening test.

```sh
xvfb-run -a prove -I. -Ilib t/*.t
```

Final 16-bit stereo PCM output saturates at -32768..32767 instead of wrapping
loud peaks into inverted audio. Normal-level samples keep their existing bytes;
raw synthesis samples and FM modulation retain their original headroom. This
applies to playback, sliced playback and WAV export. Lower voice gain if you
want to avoid hard-clipping distortion altogether.

## Musical FM explorer

The GUI now offers a musically biased alternative to the old independent-knob
**Mutate** button:

1. Choose **Bass**, **Pluck**, **Bell**, **Soft keys** or **Texture**.
2. Set **Wildness** (0–100), then click **New sound** to generate and audition.
3. Click **Like this** to make the current sound the starting point for variations.
4. Click **Variation** to explore nearby brightness/envelopes without changing
   its frequency ratios or operator structure. Repeated variations start from
   the keeper, not from one another, so they do not wander indefinitely.
5. **Undo** restores the previous sound (up to 32 changes per patch this session).

New sounds prefer family-appropriate ratios and linked amplitude/modulation
shapes. Bass/pluck/keys favour harmonic relationships; bells/textures deliberately
include inharmonic ratios. Higher Wildness permits more detuning and unusual
ratios. The renderer's PCM modulator levels are derived from frequency deviation
rather than arbitrary volume percentages. Carrier pitch stays stable and generated
levels/durations are bounded. Wildness/family affect **New sound**; **Variation**
remains gentle. The sequencer stops before changing a sound, and auditions use the
existing playback path (including chord memory when enabled).

**Like this is not a disk save.** The keeper and Undo history are session-only;
use File → Save to persist the patch bank. Audio buffers and Tk
objects are not copied into Undo history. A generation/render/playback exception
restores the previous sound and cache without consuming history. The old raw
`Patch::mutate` API remains available to existing callers.

The generator is intentionally biased, not an automatic judge of musical quality.
Headless tests render every family at low/high Wildness and check finite,
non-silent, unclipped samples and silent tails; Windows listening tests are still
needed to tune the results. Spectral headroom is a reference-note heuristic, not
an anti-aliasing filter or a guarantee for every transposition.

A silent demo renders waveforms and prints their sizes without opening audio:

```sh
perl examples/fm_patch_explorer.pl
```


## Saving and loading patch banks

- **File → Save / Save As…** saves all patches in a versioned `.synth.json` bank.
- **File → Open…** restores the bank and selected patch. Ctrl+S and Ctrl+O work too.
- Voices, nested FM modulators, envelopes and playback chord-memory settings are
  included. Rendered audio, channels, device handles and GUI objects are not.
- Loading rebuilds real Patch/Voice objects and renders the selected sound; it
  does not start playback. A failed parse or selected-sound render keeps the
  current bank. Saving writes a temporary file beside the destination before
  replacement; an unsuccessful write/replacement retains the previous file.
- WAV-based voices reference files, not embedded audio. Paths are relative to
  the bank where possible: keep those samples alongside it when moving banks.
  Missing WAVs are not recreated; a missing sample prevents rendering its patch.
- Sequencer patterns, explorer keeper/Undo history and other session state are
  not saved. There is no automatic startup load or exit save: save before closing.

**Older dumps:** File → Import legacy JSON… uses the optional `JSON::Syck`
module to recover settings from the old whole-object format, ignoring cached
binary audio and runtime state. The repository's historical `patches.json` was
checked with this importer. Import forces Save As, preserving the original dump.
Valid standard-JSON old dumps can also be opened with the normal reader.

New banks use core `JSON::PP`; XML or object-serialisation libraries are not
needed. Local `*.synth.json` banks are git-ignored. Do not commit personal sample
assets or private paths to the public repository.


## Exporting a sound

**File → Export sound as WAV…** renders the selected patch at its reference
note (C3) and saves a standard 16-bit stereo PCM WAV at the bank's sample rate.
Use it in a DAW or sampler; transpose it there from the reference note.
This is separate from saving an editable patch bank. It does not record the
sequencer or add playback chord memory. A legacy baked chord is part of the
patch itself and remains included, just as in its rendered sound.
Export does not play audio. It writes a temporary file beside the destination
and replaces the destination only after a successful write; failures keep an
existing file. No non-16-bit or non-stereo format is silently relabelled.
Keep personal exported audio out of this public repository.


## Noise levels

Tuned and untuned noise are centred around zero instead of carrying a large
positive DC offset. The random range is shifted, not doubled: at 16 bits it is
-16384 through 16383 before voice gain/envelopes. This retains the previous
noise's AC energy without an automatic loudness boost. Tuned sample-and-hold
boundaries and existing gain/decay timing are unchanged.

## Choosing a WAV sample for a voice

Select **file** in a voice's waveform menu, then use **Choose WAV...** to browse
for a sample. A compact filename is shown underneath. File voices nested as FM
modulators have the same chooser. Choosing file without an existing sample opens
the dialog first; cancelling restores the previous waveform selection.

Selection validates the WAV and renders the current patch silently. It does not
automatically audition the sample. The sequencer stops before a valid sound
change. Cancel does nothing; validation or rendering failure keeps the old voice
settings, sample reference, cached PCM and transpose frequency, and leaves the
GUI usable. Switching to sine/noise keeps the sample reference for switching
back. The default bundled sample now uses a portable path beside the program.

This uses the current file renderer, not a new audio conversion engine: choose
standard uncompressed **16-bit stereo PCM WAV** at the synth's sample rate
(normally **44100 Hz**). Mono, different bit depths/rates, compressed/extensible
formats and empty/broken files are rejected with an explanation instead of being
silently misinterpreted. Convert unsupported files first.

Banks keep their existing relative sample-reference format, without embedding
recordings. Keep external samples with the bank when moving it. Never commit
personal recordings or local user banks to this public repository.

Silent generated-fixture checks (with the usual Perl/Tk dependencies installed):

```
xvfb-run -a prove -I. -Ilib t/voice_sample.t t/voice_sample_tk.t t/full_gui_tk.t
```

These cover real selection/rendering, cancellation, invalid formats/files,
nested voices, partial render rollback, bank references and actual Tk callbacks.
They never open audio hardware. Native Windows audio still needs a listening test.
