class_name MoleculeSpecimen
extends RefCounted
## Shared pre-rendered fragment atlas. Geometry stays live in MoleculeView.
## Illustrative medicinal-chemistry motifs, not a valence-valid chemistry simulator.
const CELLS := {"fluoro": 0, "methyl": 1, "hydroxyl": 2, "phenyl": 3,
	"morpholine": 4, "nitro": 5, "amide": 6, "sulfonamide": 7,
	"tbutyl": 8, "pyridine": 9, "cyclopropyl": 10, "acid": 11,
	"core": 12, "carbon": 13, "hydrogen": 14, "chain": 15}
# Extent in scaffold units: a fluorine substituent must not be as large as a ring.
const EXTENT := {"fluoro": 0.48, "methyl": 0.78, "hydroxyl": 0.65, "phenyl": 1.52,
	"morpholine": 1.42, "nitro": 0.96, "amide": 1.20, "sulfonamide": 1.28,
	"tbutyl": 1.20, "pyridine": 1.52, "cyclopropyl": 0.98, "acid": 0.98,
	"core": 1.90, "carbon": 0.23, "hydrogen": 0.18, "chain": 1.0}
static var _regions: Dictionary = {}


static func region(id: String) -> Rect2:
	var texture := UIKit.art("molecular-fragments")
	if texture == null:
		return Rect2()
	if _regions.is_empty():
		var img := texture.get_image()
		var cell_size := Vector2i(img.get_width() / 4, img.get_height() / 4)
		for key in CELLS:
			var index: int = CELLS[key]
			var cell := Rect2i(Vector2i(index % 4, index / 4) * cell_size, cell_size)
			# Use alpha bounds so padding in the production atlas cannot change atom scale.
			var tile := img.get_region(cell)
			var mask := BitMap.new()
			mask.create_from_image_alpha(tile, 0.2)
			var used := Rect2()
			for contour in mask.opaque_to_polygons(Rect2i(Vector2i.ZERO, cell_size), 1.0):
				var part := Rect2(contour[0], Vector2.ZERO)
				for point in contour:
					part = part.expand(point)
				# Ignore stray alpha specks; include every substantial disconnected atom.
				if part.get_area() > cell_size.x * cell_size.y * 0.002:
					used = part if used.size == Vector2.ZERO else used.merge(part)
			if used.size == Vector2.ZERO:
				used = Rect2(tile.get_used_rect())
			used = used.grow(2).intersection(Rect2(Vector2.ZERO, Vector2(cell_size)))
			_regions[key] = Rect2(used.position + Vector2(cell.position), used.size)
	return _regions.get(id, _regions.get("carbon", Rect2()))


static func bounds(id: String, center: Vector2, unit: float) -> Rect2:
	var source := region(id)
	var extent := float(EXTENT.get(id, 0.8)) * unit
	var dimensions := source.size / maxf(1.0, maxf(source.size.x, source.size.y)) * extent
	return Rect2(center - dimensions * 0.5, dimensions)


static func draw_fragment(canvas: CanvasItem, id: String, center: Vector2, unit: float, tint := Color.WHITE) -> void:
	var texture := UIKit.art("molecular-fragments")
	if texture == null:
		return
	canvas.draw_texture_rect_region(texture, bounds(id, center, unit), region(id), tint)
