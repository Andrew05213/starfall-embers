# Godot bridge

This module exposes the engine-independent simulation through an official `godot-cpp`
GDExtension. Its API must stay coarse-grained:

- input: command batches and fixed-step requests;
- output: event batches, dirty chunk batches, and read-only debug snapshots;
- forbidden: one native boundary crossing per pixel.

The bridge is optional in the default native preset. It uses the pinned `godot-cpp`
10.0.0-rc1 submodule and generates bindings for the Godot 4.6 API compatibility floor.

`StarfallSimulationHost` accepts packed spawn, retire, collision-proxy, and terrain-grid arrays,
advances one fixed step, and returns packed state/event dictionaries. Invalid array shapes and invalid signed IDs reject
the whole submission. Once a structurally valid spawn batch is accepted, `sim_core` evaluates
each command's finite values, lifetime, and gravity scale at the next fixed step; invalid entries
produce `rejected` events without cancelling valid siblings.
Projectile events accumulate across catch-up ticks and are consumed only by
`drain_projectile_event_batch()`, so a slow render frame cannot silently lose events.

Packed integer codes are stable at this migration boundary:

- retire reasons: `0 = impact`, `1 = external`;
- event kinds: `0 = spawned`, `1 = expired`, `2 = retired_on_impact`,
  `3 = retired_external`, `4 = rejected`, `5 = hit_entity`, `6 = hit_terrain`.

Collision input is one coarse snapshot per fixed step: target circles/boxes and the complete
material byte grid cross the boundary in packed arrays. Native code resolves continuous projectile
hits and returns stable collider IDs; it never calls Godot once per target or terrain pixel.

`configure_primary_gravity()` and `reset_to_gate1_baseline()` replace the native host and therefore
discard active projectiles, queued commands, and undrained events. Call them only at scene/reset
boundaries.
