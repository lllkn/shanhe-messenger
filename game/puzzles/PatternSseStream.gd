extends Node
## HTTPClient 分片接收 SSE。完整 UTF-8 行到达后才解码，支持中文和任意网络切片。
signal text_received(text: String)
var _http: HTTPClient
var _wire := PackedByteArray()
var _event_lines: Array[String] = []
var _finished := false
var _invalid := false
var _content := ""
var _last_activity := 0

func _exit_tree() -> void:
	if _http != null:
		_http.close()

func feed_bytes(chunk: PackedByteArray) -> void:
	_wire.append_array(chunk)
	if _wire.size() > 262144:
		_invalid = true
		return
	var newline := _wire.find(10)
	while newline >= 0:
		var line := _wire.slice(0, newline).get_string_from_utf8().trim_suffix("\r")
		_wire = _wire.slice(newline + 1)
		if line.is_empty():
			_dispatch_event()
		elif line.begins_with("data:"):
			_event_lines.append(line.trim_prefix("data:").strip_edges())
		newline = _wire.find(10)

func _dispatch_event() -> void:
	if _event_lines.is_empty():
		return
	var data := "\n".join(_event_lines)
	_event_lines.clear()
	if data == "[DONE]":
		_finished = true
		return
	var event: Variant = JSON.parse_string(data)
	if not (event is Dictionary):
		_invalid = true
		return
	var choices: Variant = event.get("choices", [])
	if not (choices is Array):
		_invalid = true
		return
	if choices.is_empty():
		return # 某些服务最后一个事件只有 usage。
	if not (choices[0] is Dictionary):
		_invalid = true
		return
	var delta: Variant = choices[0].get("delta", {})
	if not (delta is Dictionary):
		_invalid = true
		return
	var text: Variant = delta.get("content", "")
	if text is String and not text.is_empty():
		_content += text
		_last_activity = Time.get_ticks_msec()
		text_received.emit(text)
	var finish: Variant = choices[0].get("finish_reason", null)
	if finish == "stop":
		_finished = true
	elif finish != null:
		_invalid = true # token 截断不能当作完整画稿。

func _result(ok: bool, reason: String, retryable: bool = true, code: int = 0) -> Dictionary:
	if _http != null:
		_http.close()
	return {"ok": ok, "reason": reason, "retryable": retryable, "code": code, "content": _content}

func _expired(timeout: float, started: int, total_timeout: float) -> bool:
	return Time.get_ticks_msec() - _last_activity > timeout * 1000 or Time.get_ticks_msec() - started > total_timeout * 1000

func chat(endpoint: String, key: String, payload: Dictionary, timeout: float) -> Dictionary:
	var regex := RegEx.new()
	regex.compile("^(https?)://([^/:?#]+)(?::([0-9]+))?(/[^#]*)?$")
	var url := regex.search(endpoint)
	if url == null:
		return _result(false, "服务地址配置错误", false)
	var secure := url.get_string(1) == "https"
	var port := int(url.get_string(3)) if not url.get_string(3).is_empty() else (443 if secure else 80)
	var path := url.get_string(4) if not url.get_string(4).is_empty() else "/"
	_http = HTTPClient.new()
	_http.read_chunk_size = 4096
	var started := Time.get_ticks_msec()
	_last_activity = started
	var total_timeout := maxf(timeout * 2.0, 10.0)
	var err := _http.connect_to_host(url.get_string(2), port, TLSOptions.client() if secure else null)
	if err != OK:
		return _result(false, "无法连接服务")
	while _http.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING]:
		_http.poll()
		if _expired(timeout, started, total_timeout):
			return _result(false, "等待模型超时")
		await get_tree().process_frame
	if _http.get_status() != HTTPClient.STATUS_CONNECTED:
		return _result(false, "无法连接流式服务（%d）" % _http.get_status())
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: text/event-stream", "Authorization: Bearer " + key])
	err = _http.request(HTTPClient.METHOD_POST, path, headers, JSON.stringify(payload))
	if err != OK:
		return _result(false, "请求配置错误（%d）" % err, false)
	while _http.get_status() == HTTPClient.STATUS_REQUESTING:
		_http.poll()
		if _expired(timeout, started, total_timeout):
			return _result(false, "等待模型超时")
		await get_tree().process_frame
	if not _http.has_response():
		return _result(false, "服务没有返回响应")
	var code := _http.get_response_code()
	var body := PackedByteArray()
	while _http.get_status() == HTTPClient.STATUS_BODY:
		_http.poll()
		var chunk := _http.read_response_body_chunk()
		if code == 200:
			feed_bytes(chunk)
			if _invalid or _content.length() > 65536:
				return _result(false, "流式画稿未完整返回")
			if _finished:
				return _result(true, "", false, code)
		else:
			body.append_array(chunk)
			if body.size() > 4096:
				break
		if _expired(timeout, started, total_timeout):
			return _result(false, "等待模型超时")
		await get_tree().process_frame
	if code != 200:
		var reason := "服务返回 HTTP %d" % code
		if code == 401 or code == 403:
			reason = "密钥或访问权限无效"
		push_warning("[PuzzlePattern] 流式 HTTP %d: %s" % [code, body.get_string_from_utf8().replace(key, "[redacted]").left(200)])
		return _result(false, reason, code == 408 or code == 429 or code >= 500, code)
	return _result(false, "作画中途断流")
