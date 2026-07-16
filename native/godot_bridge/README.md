# Godot bridge

This module will expose the engine-independent simulation through an official `godot-cpp`
GDExtension. Its API must stay coarse-grained:

- input: command batches and fixed-step requests;
- output: event batches, dirty chunk batches, and read-only debug snapshots;
- forbidden: one native boundary crossing per pixel.

The bridge is disabled by default until a Godot 4.7-compatible `godot-cpp` revision is pinned.
