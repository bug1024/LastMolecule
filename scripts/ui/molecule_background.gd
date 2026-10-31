class_name MoleculeBackground
extends Control
## Archival desk layer. Keep the texture cached for the whole draw lifetime.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(queue_redraw)


func _draw() -> void:
	var texture := UIKit.art("archive-desk")
	if texture:
		draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), UIKit.PAPER)
	draw_rect(Rect2(Vector2(12, 12), size - Vector2(24, 24)), Color(UIKit.BRASS, 0.55), false, 1.0)
	draw_rect(Rect2(Vector2(17, 17), size - Vector2(34, 34)), Color(UIKit.BRASS, 0.22), false, 1.0)
