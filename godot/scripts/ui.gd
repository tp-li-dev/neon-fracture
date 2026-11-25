extends Node
## UI hook bus (milestone 3 fills real screens). Sim code calls UI.hook("name", [args]);
## it is a no-op until a handler named `h_<name>` exists on this node.
func hook(name: String, args: Array = []) -> Variant:
	var m := "h_" + name
	if has_method(m):
		return callv(m, args)
	return null
