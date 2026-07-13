Tests are designed for studio since they need instances.

To run tests grab the .rbxm under `tests/reel_tests.rbxm'

Then require it and run it like so:
```luau
local run = require(game.ReplicatedStorage.reel_tests)

run()
```

Change the path to wherever you put it, you might also need to change the path to reel in the actual ModuleScript.