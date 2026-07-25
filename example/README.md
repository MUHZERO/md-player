# md_player_android example

This Android example demonstrates:

- legacy controls, which remain the default;
- opt-in modern controls in embedded and fullscreen layouts;
- host-owned orientation and fullscreen state;
- explicit process-level Media3 cache configuration;
- custom modern-control labels and accent color; and
- retry handling for invalid or unavailable URLs.

Paste a YouTube, Vimeo, or direct media URL that you are authorized to play.
Network-provider examples depend on provider availability and may stop working
when stream URLs or response formats change.

The generated files under `assets/phase_2_1/` are synthetic integration-test
fixtures. The interactive example does not load them.
