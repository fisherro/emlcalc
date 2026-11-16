## A path that builds on what works

1. **Expand mode:** add a mode to `eml`, for example `eml --expand`, that prints the input with every macro replaced by its definition instead of evaluating it. It's a small change, and it shows exactly what's left between you and the two buttons: the `swap`, `dup` and literal numbers in the output.
2. **Strict mode:** add a mode, for example `eml --strict`, that accepts only `1` and `eml`. That's the README's emleval, and the current program can enforce it with a flag. Stack manipulations like swap and dup that don't compute anything will be allowed in strict mode.
3. **Translator:** write emls2e to work on trees. Each definition from `library.eml` becomes a tree-rewriting rule, numbers get built from 1, and the output is pure `1`/`eml` in RPN. Its output goes into strict mode, which checks the claim from start to finish.
4. **Infix input (emli2s):** this comes last. It's a standard parsing job and independent of everything else.

Your `tests/run.sh` would carry over: every calculation that works today should give the same answer through strict mode, within the rounding error.
