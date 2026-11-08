# synth
Perl/TK synthesizer

*To Do*

- serialise settings (patches, synth etc) to json
    - try moosex-storage
        - seems to blow up on Patches (actually nested objects)
            - looks like storagex can't go recursive?
                - MooseX::Role::JSONObject didn't work
                    - Irole my own saving system. for each object have a save method that returns up json or something?
                - JSON::Syck; worked, though it includes all the binary data of the sample too. Who cares if it works! https://stackoverflow.com/a/3408107/74585
                
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
the last value. Existing -1000..1000 limits remain. External voice changes refresh
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


## Playback chord memory

Turn on **Chord memory** and choose Major, Minor, Major 7th, Minor 7th,
Dominant 7th, Sus2, Sus4 or Octave. Each keyboard note triggers the already-rendered
sample on independent playback channels: Major 7th uses 0, 4, 7 and 11 semitones.
Changing this setting does **not** regenerate or rewrite the patch. Release the
key to stop all its voices; changing presets while held does not change release
behaviour. The on-screen piano buttons play one-shot chords.

The older sample-generation **Baked chord (legacy)** option remains available.
The GUI's default bass patch now starts with that option off, so playback chord
memory builds harmony from a single-note sample rather than stacking chords.
Other patches that already contain a chord will still transpose that whole chord.

Active voices get separate slots, growing as needed rather than wrapping over a
held note. Completed/released slots are reused. This is not literally unlimited
hardware polyphony: the Windows audio driver may impose its own device limits.
A partial chord failure releases the voices already started.

## Mini sequencer

**Randomise & Play** generates and immediately loops a new 16-step phrase.
Keep clicking until you hear something you like; **Play** repeats the current
phrase, **Stop** silences it. Tempo is 40–240 BPM with sixteenth-note steps.
Choose a major, minor or minor-pentatonic scale for the next randomisation.
The numbered buttons show notes/rests; click to mute or restore a step.
The GUI's selected keyboard octave determines the root C. Chord memory applies
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
use the existing Save action to persist the current patch. Audio buffers and Tk
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
