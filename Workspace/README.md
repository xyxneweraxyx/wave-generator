# Wave Generator — Procedural Ocean Wave Renderer
 
A server-side bone-based wave engine for Roblox. Given a MeshPart ocean with bones, it pre-computes every frame of a wave pass and plays it back in real time. The wave shape, noise, foam, and texture scrolling are fully configurable.
 
## How it works
 
1. `createWave(params)` reads all bones from the ocean MeshParts, sorts them by their axis position, and pre-computes a `bulkMoves` table — one `CFrame` per bone per frame — using a sigmoid-like height formula with layered Perlin noise. Foam emitter positions are also pre-computed if enabled.
2. `playWave(wave)` iterates through the pre-computed frames at the target FPS, bulk-setting bone CFrames each tick. Ocean texture `OffsetStudsV` is scrolled in a parallel thread.
3. Creation is spread across frames (`framesLoadedPerFrame`) to avoid hitching during load.
 
## Key parameters (`waveParams`)
 
| Parameter | Description |
|-----------|-------------|
| `ocean` | Table of MeshParts containing bones |
| `axis` / `direction` | Wave travel axis and direction |
| `speed`, `height`, `amplitude`, `steepness` | Wave shape |
| `noiseMaxAdd`, `noiseRoughnessX/Y/Z` | Noise intensity and scale |
| `noiseApplyMode` | `allWave` or `towardsCenter` (easing noise at edges) |
| `isFoam`, `foamEmitter`, `foamThicknessFactor` | Optional foam particles on the wave crest |
| `fps`, `framesLoadedPerFrame` | Performance tradeoff |
 
## Author
 
Roblox project, 2025