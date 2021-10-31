# synth
Perl synthesizer

- serialise settings (patches, synth etc) to json
    - try moosex-storage
        - seems to blow up on Patches (actually nested objects)
            - looks like storagex can't go recursive?
                - MooseX::Role::JSONObject didn't work
                    - I suppose I could hand role my own saving system. for each object have a save method that returns up json or something?
                - anyway JSON::Syck; worked, though it includes all the binary data of the sample too. Who cares if it works! https://stackoverflow.com/a/3408107/74585
                

Originally sponsored by [PICA](https://pica.org.au/)