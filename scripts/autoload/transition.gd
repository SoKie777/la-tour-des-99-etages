extends CanvasLayer
## Fondu entre les écrans : à chaque changement de scène, l'image sort du noir.

var veil: ColorRect


func _ready() -> void:
	layer = 100
	veil = ColorRect.new()
	veil.color = Color(0.03, 0.02, 0.06, 0.0)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	get_tree().scene_changed.connect(_on_scene_changed)


func _on_scene_changed() -> void:
	veil.color.a = 1.0
	var tw := create_tween()
	tw.tween_property(veil, "color:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
