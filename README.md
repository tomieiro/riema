# Riema

Riema is a pure-Lua environment manager for Lua runtimes and LuaRocks packages.
The project targets a Conda-like workflow for named environments, isolated
dependency trees, activation helpers, and YAML-based environment definitions.

This repository currently provides a Phase 1 baseline:

- original Lua CLI entrypoint
- local registry and package store under `~/.riema` or `RIEMA_HOME`
- binary download/install for Lua and LuaRocks on Linux x86_64
- environment metadata and directory layout
- shell activation script generation
- `run`, `list`, `info`, `remove`, `doctor`
- `create env --name ...`, `env create -f`, and `env export`
- package intent tracking for future LuaRocks integration

Current non-goals for this baseline:

- runtime compilation from source
- lockfile resolution

## Quick start


Before start, init the riema for shell:

```bash
eval "$(./riema init --shell bash)"
```

or you could persist the init in .bashrc:

```bash
eval "$(./riema init --shell bash --persist)"
source ~/.bashrc
```

Finally, create your env and activate it!


```bash
riema create env --name dev lua=5.4 luarocks=3.12
riema activate dev
riema info dev
riema env export dev
riema run dev lua -e 'print(os.getenv("RIEMA_ENV_NAME"))'
riema deactivate
```

Create from YAML:

```bash
./riema env create -f env.yml
```

Example `env.yml`:

```yaml
name: dev
lua: "5.4"
luarocks: "3.12"
packages:
  - busted
  - luafilesystem
  - luasocket
```

## Layout

- `riema`: CLI entrypoint
- `lua/riema`: application modules
- `test/test_cli.lua`: smoke tests for registry, YAML, activation, and run

## Notes

- Riema stores registry state in Lua data files and keeps downloaded/runtime
  artifacts under `~/.riema/pkgs`, with environments under `~/.riema/envs`.
- `riema create env --name dev lua=5.4 luarocks=3.12` resolves minor aliases to
  exact release artifacts and downloads them into the environment.
- `riema init --shell bash` installs a shell wrapper so `riema activate <env>`
  and `riema deactivate` act on the current shell, similar to Conda.
- `riema init --shell bash --persist` writes the hook to `~/.bashrc` so the
  wrapper is available in future shells too.
- After loading the hook, use `riema activate ...` and `riema deactivate`.
  Do not use `./riema activate ...` or `./riema deactivate`, because those run
  as plain subprocesses and cannot modify the current shell.
- Without `riema init`, `./riema activate <env>` prints the `source ...`
  command needed to activate the environment manually.
- Activation scripts are generated for `bash`, `zsh`, `fish`, `csh`, Windows
  batch, and PowerShell.
- The generated LuaRocks config is local to each environment and points the
  rocks tree at the environment prefix.

## Inspiration for work

Riema is inspired by Hererocks by Peter Melnichenko. This repository does not
reuse the Hererocks Python implementation.
