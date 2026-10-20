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
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_idx := 0
var _sfx_lib: Dictionary = {}
var _blur: Shader


func _ready() -> void:
	_click = AudioStreamPlayer.new()
	_click.stream = _make_click()
	_click.volume_db = -14.0
	add_child(_click)
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.volume_db = -10.0
		add_child(p)
		_sfx_pool.append(p)
	get_tree().node_added.connect(_on_node_added)


## Joue un effet sonore procédural (slash, hit, crit, ult, break, heal, buff, debuff, victory, defeat).
func play_sfx(kind: String, pitch := 1.0) -> void:
	if DisplayServer.get_name() == "headless" or _sfx_pool.is_empty():
		return
	if not _sfx_lib.has(kind):
		_sfx_lib[kind] = _synth(kind)
	var p: AudioStreamPlayer = _sfx_pool[_sfx_idx]
	_sfx_idx = (_sfx_idx + 1) % _sfx_pool.size()
	p.stream = _sfx_lib[kind]
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.play()


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


## Synthèse procédurale d'effets sonores de combat et d'interface (tambour taiko, lame, cristal, koto).
func _synth(kind: String) -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.22
	match kind:
		"ult", "victory", "defeat":
			dur = 0.55
		"break", "heal":
			dur = 0.38
		"crit":
			dur = 0.28
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = kind.hash()
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var v := 0.0
		match kind:
			"slash":
				var env := sin(minf(1.0, t / 0.16) * PI) * exp(-t * 14.0)
				lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.28)
				var f := lerpf(920.0, 240.0, minf(1.0, t / 0.16))
				v = (lp * 0.65 + sin(TAU * f * t) * 0.35) * env
			"hit":
				var env := exp(-t * 26.0)
				lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.4)
				var f := lerpf(190.0, 58.0, minf(1.0, t / 0.12))
				v = (sin(TAU * f * t) * 0.75 + lp * 0.35 * exp(-t * 45.0)) * env
			"crit":
				var env := exp(-t * 16.0)
				lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.5)
				var sub := sin(TAU * lerpf(240.0, 52.0, minf(1.0, t / 0.15)) * t)
				var ring := sin(TAU * 1320.0 * t) * 0.35 + sin(TAU * 1980.0 * t) * 0.25
				v = (sub * 0.7 + ring * exp(-t * 12.0) + lp * 0.3 * exp(-t * 40.0)) * env
			"break":
				var env := exp(-t * 10.0)
				var chime := sin(TAU * 1568.0 * t) * 0.4 + sin(TAU * 2349.0 * t) * 0.3 + sin(TAU * 3136.0 * t) * 0.25
				var boom := sin(TAU * lerpf(160.0, 42.0, minf(1.0, t / 0.25)) * t) * 0.65
				lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.6)
				v = (chime + boom + lp * 0.35 * exp(-t * 25.0)) * env
			"ult":
				var env := minf(1.0, t / 0.04) * exp(-t * 4.8)
				var f0 := 220.0 + 110.0 * smoothstep(0.0, 0.35, t)
				v = (sin(TAU * f0 * t) * 0.45 + sin(TAU * f0 * 1.5 * t) * 0.35 + sin(TAU * 82.0 * t) * 0.4) * env
			"heal":
				var notes := [523.25, 659.25, 783.99, 1046.5]
				var idx := clampi(int(t / 0.085), 0, 3)
				var nt := fmod(t, 0.085)
				v = sin(TAU * notes[idx] * t) * exp(-nt * 18.0) * 0.65
			"buff":
				var f := 523.25 if t < 0.09 else 783.99
				v = (sin(TAU * f * t) * 0.6 + sin(TAU * f * 2.0 * t) * 0.2) * exp(-fmod(t, 0.09) * 16.0)
			"debuff":
				var f := 349.23 if t < 0.1 else 233.08
				v = (sin(TAU * f * t) * 0.6 + sin(TAU * f * 1.414 * t) * 0.25) * exp(-t * 9.0)
			"victory":
				var notes := [523.25, 659.25, 783.99, 1046.5]
				var idx := clampi(int(t / 0.11), 0, 3)
				v = (sin(TAU * notes[idx] * t) * 0.55 + sin(TAU * notes[idx] * 0.5 * t) * 0.3) * exp(-fmod(t, 0.11) * 8.0)
			"defeat":
				var notes := [329.63, 293.66, 220.0]
				var idx := clampi(int(t / 0.17), 0, 2)
				v = sin(TAU * notes[idx] * t) * exp(-fmod(t, 0.17) * 6.0) * 0.6
			_:
				v = sin(TAU * 440.0 * t) * exp(-t * 20.0) * 0.5
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 22000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w
