# Contributing to Mainstream

Mainstream should be comfortable on someone's first Linux computer and useful to the people who know exactly how they want theirs to work. Fixes, ideas, translations and honest feedback all help get it there. A one-line fix is welcome.

If something is broken, [report it](https://github.com/MainstreamOS/dots-hyprland/issues). If you'd like help, want to talk through an idea, or would like to build something together, start a [discussion](https://github.com/MainstreamOS/dots-hyprland/discussions) or join the [Mainstream Discord](https://discord.gg/WJ3AUK5Aqd). You don't need a finished solution to join in.

## Sending a change

Keep each pull request focused on one problem or feature. Leave unrelated local preferences and cleanup for another PR so the change is easy to understand and test. If a default needs to change, explain why and what that means for people already using it.

Describe what changes for the person using Mainstream and how you checked it. Screenshots help with visible changes. Say what you couldn't test, and use a draft PR if you'd like feedback while you're still working.

For a larger feature, discussing the approach first can save work. Features that suit a particular workflow can often be offered as an option without making everyone use them.

## Keeping the desktop practical

Make everyday use clear and predictable. Check that a change still works with keyboard navigation, smaller displays and different scaling where relevant. Keep text readable across light and dark colors and translucent surfaces.

Optional effects and features should only load when needed. Use a `Loader` for an optional component, with its layout and anchors on the loader. `FadeLoader` can animate visibility when the component doesn't need to change its parent's layout.

Consider the cost on older graphics cards and laptops. An effect should earn the resources it uses. Keep expensive extras optional, and avoid adding work to every frame when the underlying content hasn't changed.

Match the surrounding QML style: spaces around operators, properties grouped by purpose, and early returns where they make the code easier to follow. Split reusable pieces into a component or file when that makes the behavior clearer.

## Translations

The current [translation guidance](../dots/.config/quickshell/ii/translations/TERMINOLOGY.md) explains Mainstream's terminology and locale decisions. The [maintenance tools](../dots/.config/quickshell/ii/translations/tools/README.md) check coverage and formatting. Preserve existing translations and exact placeholders, commands and paths.

If you'd like to help with a language but don't use Git, [open an issue](https://github.com/MainstreamOS/dots-hyprland/issues), start a [discussion](https://github.com/MainstreamOS/dots-hyprland/discussions), or join the [Mainstream Discord](https://discord.gg/WJ3AUK5Aqd) and tell us which language you'd like to work on. Familiar wording and small corrections matter as much as a full translation pass.
