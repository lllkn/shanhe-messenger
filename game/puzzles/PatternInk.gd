extends RefCounted
## 小型矢量笔触协议：曲线、椭圆、花瓣。模型只给控制点，程序采样光滑轨迹。
const BOARD_SIZE := Vector2(630, 400)
const DESIGN_SIDE := 352.0
const DESIGN_ORIGIN := (BOARD_SIZE - Vector2.ONE * DESIGN_SIDE) * 0.5

var _fragment := ""
var _depth := 0
var _quoted := false
var _escaped := false

func feed_commands(text: String) -> Array:
	var commands: Array = []
	for ch in text:
		if _depth == 0:
			if ch != "{":
				continue
			_fragment = ""
			_quoted = false
			_escaped = false
		_fragment += ch
		if _quoted:
			if _escaped:
				_escaped = false
			elif ch == "\\":
				_escaped = true
			elif ch == '"':
				_quoted = false
		else:
			if ch == '"':
				_quoted = true
			elif ch == "{":
				_depth += 1
			elif ch == "}":
				_depth -= 1
				if _depth == 0:
					var json := JSON.new()
					if json.parse(_fragment) == OK and json.data is Dictionary:
						commands.append(json.data)
		if _fragment.length() > 8192:
			_depth = 0
			_fragment = ""
	return commands

static func _number(data: Dictionary, key: String, lo: float, hi: float, fallback: float = NAN) -> float:
	var value: Variant = data.get(key, fallback)
	if not (value is int or value is float) or not is_finite(float(value)):
		return NAN
	var number := float(value)
	return number if number >= lo and number <= hi else NAN

static func _cubic(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, out: PackedVector2Array) -> void:
	for i in range(1, 33):
		var t := float(i) / 32.0
		var u := 1.0 - t
		out.append(u*u*u*p0 + 3*u*u*t*p1 + 3*u*t*t*p2 + t*t*t*p3)

static func command_to_stroke(command: Dictionary) -> PackedVector2Array:
	var raw := PackedVector2Array()
	var op: String = str(command.get("op", ""))
	if op == "path":
		var points: Variant = command.get("p", null)
		if not (points is Array) or points.size() < 4 or points.size() > 25 or (points.size() - 1) % 3 != 0:
			return raw
		var controls := PackedVector2Array()
		for point in points:
			if not (point is Array) or point.size() != 2:
				return PackedVector2Array()
			if not (point[0] is int or point[0] is float) or not (point[1] is int or point[1] is float):
				return PackedVector2Array()
			var pos := Vector2(float(point[0]), float(point[1]))
			if not is_finite(pos.x) or not is_finite(pos.y) or pos.x < 0 or pos.x > 100 or pos.y < 0 or pos.y > 100:
				return PackedVector2Array()
			controls.append(pos)
		raw.append(controls[0])
		for i in range(0, controls.size() - 1, 3):
			_cubic(controls[i], controls[i+1], controls[i+2], controls[i+3], raw)
	elif op == "ellipse" or op == "petal" or op == "flower":
		var x := _number(command, "x", 0, 100)
		var y := _number(command, "y", 0, 100)
		var a := _number(command, "a", -360, 360, 0)
		if is_nan(x) or is_nan(y) or is_nan(a):
			return raw
		var center := Vector2(x, y)
		if op == "ellipse":
			var rx := _number(command, "rx", 0.5, 48)
			var ry := _number(command, "ry", 0.5, 48)
			if is_nan(rx) or is_nan(ry):
				return raw
			for i in 65:
				var angle := TAU * float(i) / 64.0
				raw.append(center + Vector2(cos(angle)*rx, sin(angle)*ry).rotated(deg_to_rad(a)))
		elif op == "flower":
			var radius := _number(command, "r", 2, 45)
			var petals := _number(command, "petals", 3, 20)
			if is_nan(radius) or is_nan(petals):
				return raw
			for i in 193:
				var angle := TAU * float(i) / 192.0
				var r := radius * (0.79 + 0.21 * cos(petals * angle))
				raw.append(center + Vector2(cos(angle), sin(angle)).rotated(deg_to_rad(a)) * r)
		else:
			var length := _number(command, "l", 2, 55)
			var width := _number(command, "w", 1, 30)
			if is_nan(length) or is_nan(width):
				return raw
			var axis := Vector2.RIGHT.rotated(deg_to_rad(a))
			var normal := axis.orthogonal()
			var tip := center + axis * length
			raw.append(center)
			_cubic(center, center + axis*length*0.30 + normal*width, center + axis*length*0.80 + normal*width, tip, raw)
			_cubic(tip, center + axis*length*0.80 - normal*width, center + axis*length*0.30 - normal*width, center, raw)
	else:
		return raw
	var out := PackedVector2Array()
	for point in raw:
		if point.x < -0.1 or point.x > 100.1 or point.y < -0.1 or point.y > 100.1:
			return PackedVector2Array()
		out.append(to_board(point))
	return out

static func to_board(point: Vector2) -> Vector2:
	# 正方形设计域等比放进画纸，圆不被横向拉成长椭圆。
	return DESIGN_ORIGIN + point * (DESIGN_SIDE / 100.0)

static func prefix(line: PackedVector2Array, fraction: float) -> PackedVector2Array:
	if line.size() < 2:
		return PackedVector2Array()
	var length := 0.0
	for i in range(1, line.size()):
		length += line[i-1].distance_to(line[i])
	var remaining := length * clampf(fraction, 0, 1)
	var out := PackedVector2Array([line[0]])
	for i in range(1, line.size()):
		var segment := line[i-1].distance_to(line[i])
		if remaining < segment:
			out.append(line[i-1].lerp(line[i], remaining / maxf(segment, 0.001)))
			break
		out.append(line[i])
		remaining -= segment
	return out
