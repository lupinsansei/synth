# synth
Perl/TK synthesizer

- To Do
- new number picker
    - build_super_number_picker2
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