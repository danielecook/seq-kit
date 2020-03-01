# Package

version       = "0.0.2"
author        = "Daniel E. Cook"
description   = "seq-collection: Sequence data utilities"
license       = "MIT"

# Dependencies

requires "colorize", "zip >= 0.2.1", "lapper"#, "ggplotnim==0.2.9"

requires "https://github.com/Vindaar/ggplotnim#b736f1fc5027a7613b8309ef774422866042685e"
requires "https://github.com/danielecook/BitVector#b8cc21271c90cca96ed31f5d5383711dc96a8d3f"
requires "https://github.com/brentp/hts-nim#423e9c87884e9ce6abe5e4b2a12168ac63fc8f53"
#requires "argparse >= 0.9.0" 
requires "https://github.com/iffy/nim-argparse#6257d1ac34607e7834eba31f459e9392d1ec06b7"

bin = @["sc"]
skipDirs = @["test"]

task test, "run tests":
  exec "bash ./scripts/functional-tests.sh"
  #exec "nim c --threads:on -d:release --lineDir:on --debuginfo -r tests/all"