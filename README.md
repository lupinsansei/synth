# synth
Perl/TK synthesizer

*To Do*

- new number picker
    - build_super_number_picker2
        - let's populate it with the textvariable
            - divide it by 10
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
- Super number spinner
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
