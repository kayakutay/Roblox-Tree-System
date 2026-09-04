# Roblox Tree Harvesting System (Client-Server Architecture)

A custom tree-harvesting system built in Roblox Luau, focused on performance optimization and clean client-server separation.

I started this project with a basic single-script prototype. However, the initial code ran all physics and animations directly on the server, which caused server lag and memory issues. I refactored the entire system into an event-driven, production-ready architecture.

---

### The Problems in the Initial Prototype

* **Server Lag:** The server was running `Heartbeat` loops and `TweenService` to move logs and scale trees. This wasted CPU cycles on purely visual effects.
* **Memory Leaks:** Respawn countdown timers were created directly in `Workspace` without cleanup events. Deleted trees left orphaned parts in memory.
* **No Hit Cooldown:** The server did not validate how fast a player clicked, leaving the system open to macro exploits.
* **Hit Race Conditions:** Fast consecutive hits triggered multiple shake loops at the same time, breaking tree orientations.

---

### Architecture & Solution

I separated game logic (server authority) from visual effects (client rendering) using `RemoteEvents`.

| Script | Location | Responsibility |
| :--- | :--- | :--- |
| **`TreeManager.lua`** | `ServerScriptService` | Server authority: Hit cooldowns, distance checks, health calculation, currency rewards. |
| **`TreeEffectsClient.lua`** | `StarterPlayerScripts` | Client rendering: Local tree shake, shrink/grow animations, and magnetic log tweens. |

---

### Key Optimizations

1. **Client-Side Drops & Tweens:**
   Logs no longer use physical server constraints. Instead, the server sends a network event (`FireClient`), and only the harvesting player renders the floating log tween locally.
2. **Anti-Exploit Cooldown:**
   Added an internal timestamp check (`os.clock()`) on the server. Hits faster than 0.35 seconds are ignored.
3. **Safe Memory Management:**
   Added `AncestryChanged` listeners. If a tree is destroyed or removed from the game, its cache data and timer instances are cleaned up immediately.
4. **State Lock:**
   Added an `IsShaking` flag on the client to prevent overlapping hit animations.

---

### Tech Stack
* **Language:** Luau (Roblox)
* **Services Used:** `CollectionService`, `TweenService`, `RunService`, `Players`, `ReplicatedStorage`
