# Start here

Project Zomboid B42 mods for one single-player save. Build context in this order and stop when you have enough:

1. `docs/save-manifest.md`: which mods are in scope and what each does. Anything not listed there (including `..\mods-archive`) is out of scope.
2. `docs/README.md`: index of the modding guide; read only the topic file the task needs.
3. `.cursor/rules/*.mdc`: working rules (load automatically in Cursor).
4. For bugs: the newest `..\ErrorMonitor\<session>\errors.txt` (SUMMARY and ERRORS sections), then `..\console.txt`.

Goals: keep the guide in `docs/` current, keep the manifest current, commit every change to the `mods\` monorepo on GitHub (`docs/environment.md` "Git"), Lua by default: a mod is Lua-only if it reasonably can be. A mod gets Java (as a ZombieBuddy plugin) only when part of it can't reasonably be done in Lua; once it has Java, other parts of that mod may use Java too. The mod must still load without it (`docs/sensible-architecture.md`, `docs/environment.md` §5).
