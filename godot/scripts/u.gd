extends Node
## Shared helpers mirroring the JS globals: TAU, clamp, rand, pick, dist2.
func clamp(v: float, a: float, b: float) -> float: return minf(b, maxf(a, v))
func rand(a: float, b: float) -> float: return randf_range(a, b)
func pick(arr: Array): return arr[randi() % arr.size()] if arr.size() > 0 else null
func dist2(a, b) -> float:
	var dx: float = a.x - b.x
	var dy: float = a.y - b.y
	return dx * dx + dy * dy
func now_ms() -> float: return float(Time.get_ticks_msec())
func has(d: Dictionary, k) -> bool: return d.has(k) and d[k] != null
