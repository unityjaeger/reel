---
title: easings
description: Supported Pose easing functions.
sidebar:
 order: 4
---

The package entry exports `easings` and `easing_map`:

```luau
local reel = require(game.ReplicatedStorage.reel)
```

`animation.load_keyframe_sequence()` selects the function in `easing_map` from each pose's `EasingStyle` and `EasingDirection`.

Supported styles are:

- Linear
- Cubic
- CubicV2
- Elastic
- Bounce
- Constant

Each supports In, Out, and InOut directions.

Easing functions are just implementation details for most callers.