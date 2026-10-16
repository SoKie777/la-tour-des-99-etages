extends Node
## « Game juice » de l'interface (autoload UiJuicer) : chaque bouton du jeu grossit au survol, s'enfonce avec
## un petit clic à l'appui et rebondit en élastique au relâchement ; pop_in() fait apparaître une fenêtre
## en fondu + zoom sur un fond flouté.

const BLUR_SHADER := """shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur_size = 3.0;
uniform vec4 tint : source_color = vec4(0.05, 0.03, 0.09, 0.45);
uniform float amount = 1.0;
void fragment() {
	vec3 c = textureLod(screen_texture, SCREEN_UV, blur_size * amount).rgb;
	COLOR = vec4(mix(c, tint.rgb, tint.a * amount), 1.0);
}
"""

var _click: AudioStreamPlayer
var _blur: Shader


func _ready() -> void:
	_click = AudioStreamPlayer.new()
	_click.stream = _make_click()
	_click.volume_db = -14.0
	add_child(_click)
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		juice(n)


## Retour tactile d'un bouton (appliqué automatiquement à tous les BaseButton).
func juice(b: BaseButton) -> void:
	if b.has_meta("juiced"):
		return
	b.set_meta("juiced", true)
	b.resized.connect(func() -> void: b.pivot_offset = b.size / 2.0)
	var to := func(s: float, t: float, trans := Tween.TRANS_QUAD) -> void:
		if not b.is_inside_tree():
			return
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(s, s), t).set_trans(trans).set_ease(Tween.EASE_OUT)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled and not b.button_pressed:
			to.call(1.05, 0.1))
	b.focus_entered.connect(func() -> void:
		if not b.disabled:
			to.call(1.05, 0.1))
	b.mouse_exited.connect(func() -> void: to.call(1.0, 0.12))
	b.focus_exited.connect(func() -> void: to.call(1.0, 0.12))
	b.button_down.connect(func() -> void:
		if b.disabled:
			return
		to.call(0.95, 0.06)
		_click.pitch_scale = randf_range(0.95, 1.08)
		_click.play())
	b.button_up.connect(func() -> void: to.call(1.0, 0.45, Tween.TRANS_ELASTIC))


## Apparition d'une fenêtre : fondu 0 -> 1 et zoom 0,9 -> 1, sur un fond flouté (blur 3).
## Renvoie le fond, à libérer avec la fenêtre (close() s'en charge).
func pop_in(panel: Control, blur := true) -> Control:
	var backdrop: ColorRect = null
	if blur and panel.get_parent() != null:
		if _blur == null:
			_blur = Shader.new()
			_blur.code = BLUR_SHADER
		backdrop = ColorRect.new()
		backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		var m := ShaderMaterial.new()
		m.shader = _blur
		m.set_shader_parameter("amount", 0.0)
		backdrop.material = m
		backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
		var parent := panel.get_parent()
		parent.add_child(backdrop)
		parent.move_child(backdrop, panel.get_index())
		var tb := backdrop.create_tween()
		tb.tween_method(func(v: float) -> void: m.set_shader_parameter("amount", v), 0.0, 1.0, 0.2)
		panel.tree_exited.connect(func() -> void:
			if is_instance_valid(backdrop):
				backdrop.queue_free())
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.9, 0.9)
	var center := func() -> void: panel.pivot_offset = panel.size / 2.0
	panel.resized.connect(center)
	center.call()
	var tw := panel.create_tween().set_parallel()
	tw.tween_property(panel, "modulate:a", 1.0, 0.18)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return backdrop


## Petit « clic » d'enfoncement synthétisé (pas de fichier audio) : bruit filtré très court.
func _make_click() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.045)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * 90.0)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.35)
		var v := (lp * 0.6 + sin(TAU * 1400.0 * t) * 0.4) * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 20000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w
