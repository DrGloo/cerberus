## Project rules: Slide Simulator (Roblox, Luau, Rojo)

A Roblox game written in Luau, synced into Studio with Rojo, client and
server. You have shipped and maintained live multiplayer games. Think like an
exploiter first: for every remote handler, purchase path, or progression write
the diff touches, ask what a modified client could send.

### Leaks and lifecycle, in this codebase
- `:Connect(...)` on `RunService.Heartbeat`, `.Touched`, `.PlayerRemoving`,
  `.Changed`, `.OnServerEvent`: each returned connection must be disconnected,
  or owned by a `Maid` that is cleaned up. `SlideController` uses a per-run
  `Maid`; new per-run resources belong to it.
- `Instance.new(...)` parented into `workspace`, a player's PlayerGui, or a
  client-local folder must be destroyed when its owner ends. `PowerUpRenderer`
  keeps `activeModels` keyed by id; anything added there needs a removal path
  on both collect and run end.
- `task.delay` / `task.spawn` closures that outlive the run they belong to and
  still touch its state after teardown.
- `TweenService` tweens and `ParticleEmitter`/`Trail` instances created per run.
- Tables keyed by player or by userId with no `Players.PlayerRemoving`
  cleanup. `ObservabilitySink` uses a bounded ring queue and `IngressGuard`
  clears its per-user state on leave; new per-player state must do the same.

### Player data
- Fields must be added to `DEFAULT_DATA` in `PlayerStatManager` so
  `EnsurePlayerFields()` migrates them. Renaming or removing a field, or
  changing the `slideSimData1` DataStore key, is a data loss path.
- Player-data writes go through the serialized per-user persistence path,
  never a direct `SetAsync`.
- Specs live in `src/server/tests/specs/*.spec.lua` and export `{ name, run }`;
  pure logic changes (physics, validation, idempotency) are expected to carry
  one.

### Concurrency patterns that have bitten this codebase
- `Event:Wait()` on an event whose `Fire()` can run before the wait is
  reached: `task.spawn` runs its thread synchronously until the first yield,
  so a worker that never yields fires "done" before the caller waits. Latch on
  an explicit flag, or the waiter parks forever.
- Two maid tasks whose *order* matters (a `BindableEvent` and a separate hook
  that fires it): `DoCleaning` runs tasks in `next()` order, so order-dependent
  teardown must be folded into a single task.
- `task.cancel` / `coroutine.close` on a thread that may already be dead
  raises and aborts the rest of the cleanup closure. Guard with
  `coroutine.status` before cancelling.

### Per-frame performance (WARN at most)
Scope: code inside `Heartbeat`, `RenderStepped`, or `Stepped` callbacks only.
A new per-frame allocation (`Instance.new`, `string.format`, a table or closure
per frame) or a new O(players)/O(models) scan is a WARN unless the diff shows a
cadence or budget guard (the `RUNTIME_BOUNDS` pattern used by `SlideRunPhysics`).

### House rules (not catchable by a linter)
1. Indentation is **tabs**.
2. Module requires use the guarded form
   `require(Shared:WaitForChild("utils", 10):WaitForChild("Foo", 10))`. A bare
   `WaitForChild` with no timeout can hang a server start forever.
3. `src/shared/vendor/` (`Maid`, `GoodSignal`) is third-party. Any change there
   is at least a WARN naming the file, and a BLOCKER if it changes a public
   method's behaviour for a task type the codebase registers (functions,
   RBXScriptConnections, Instances, nested Maids; the contract is pinned by
   `src/server/tests/specs/Maid.spec.lua`).
4. Use `task.wait` / `task.spawn` / `task.defer`. Deprecated `wait` / `spawn` /
   `delay` are a WARN.
5. `:Connect`, never `:connect`.
6. The server is authoritative. Anything the client sends is untrusted: remote
   handlers go through `IngressGuard.wrapEvent` / `wrapInvoke` and validate
   with `ValidationUtils` against the bounds in `Constants.VALIDATION`. A new
   remote handler without that wrapping is a BLOCKER.
7. Models moved with `PivotTo` must have every descendant part anchored;
   unanchored parts drift between frames.
8. Player-bound transient models set `ModelStreamingMode = Persistent` so they
   are not streamed out mid-run.
9. Tuning numbers live in `Constants` (or `shared/config/modules/*`), not
   inline at the call site.
10. Client code may render and predict; it may never be the source of truth
    for currency, unlocks, or progression.
11. No raw `print`/`warn` in game code: all debug output goes through
    `Constants.debugPrint` / `Constants.debugWarn`. Errors carry
    `debugWarn(...)` plus `ObservabilitySink.Emit(event, { severity, module,
    operation, reasonCode, userId, outcome })`.
12. Any edit to `wally.toml` or `aftman.toml` is at least a WARN naming the
    package and version; the first `require` of a `Packages/*` module no other
    file uses yet is a WARN.
