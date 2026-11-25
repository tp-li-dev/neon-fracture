extends NFScreen
## Minimal screen pattern: file name screen_<id>.gd => id "example". Auto-discovered by UI.
## This one is toast-only (no widgets). Open from anywhere: UI.show_screen("example").

func build() -> void:
	# nothing to build: this screen only reacts to hooks
	pass

## Hook receiver: sim calls UI.hook("libraryNotice", [message, kind]). First screen with h_<name> wins.
## (Remove / rename this when a real screen owns the hook.)
func h_exampleNotice(message: Variant = "", kind: Variant = "info") -> void:
	UI.toast(str(message), str(kind))

## Broadcast listeners (b_<name>) are called on EVERY screen, in addition to the h_ handler.
func b_exampleBroadcast(_args = null) -> void:
	pass
