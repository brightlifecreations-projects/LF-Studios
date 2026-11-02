# LF Studios 1.19.0: decisions made while the owner was away

Each one: the choice, and why (the safer, simpler option within the rules).

1. **15 GB free is enough** (owner's answer in the preflight). Stop before
   publishing if it drops under 6 GB.

2. **A found bug left as it is: the sound of a video on a track above the
   main track fades from full to nearly silent across the clip** (measured:
   0.31 RMS at its start, 0.06 at its end). Same cause as the muted-clip bug
   fixed in 1.18.0 (a lone volume point blends into the next one). Not fixed
   here because the rules say old projects must export identical to 1.18.0;
   fixing it changes the sound of every project with such a video. Unlinked
   sound (new in 1.19.0) uses the same mix, so linked and unlinked sound the
   same. **Owner to decide**: the fix is the 1.18.0 one (hold each item's
   level with a ramp over its length), in VideoLayerInput.apply.
