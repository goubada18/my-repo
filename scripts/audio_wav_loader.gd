class_name AudioWavLoader
extends RefCounted

## 解析 .dat 包装的标准 RIFF WAV（PCM 16-bit），返回 AudioStreamWAV。
## 绕开 Godot 对 BWF WAV 的导入崩溃（项目音效统一用 .dat + 自解析）。
## 复用点：原本 fp_viewmodel_player.gd / fp_action_retarget.gd / fp_gameplay.gd 各有一份
## 逐字节相同的 _load_sfx_wav（仅编辑器预览版多一行缺失警告）。统一抽到此处，消除三份重复。
static func load_wav(res_path: String) -> AudioStreamWAV:
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return null
	var bytes := f.get_buffer(f.get_length())
	f.close()
	if bytes.size() < 44:
		return null
	var i := 12
	var fmt := PackedByteArray()
	var data := PackedByteArray()
	while i + 8 <= bytes.size():
		var cid := bytes.slice(i, i + 4).get_string_from_ascii()
		var size: int = bytes.decode_u32(i + 4)
		var body := i + 8
		if cid == "fmt ":
			fmt = bytes.slice(body, body + mini(size, 16))
		elif cid == "data":
			data = bytes.slice(body, body + size)
		i = body + size + (size & 1)
	if fmt.size() < 16 or data.is_empty():
		return null
	var ch: int = fmt.decode_u16(2)
	var rate: int = fmt.decode_u32(4)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = ch > 1
	stream.data = data
	return stream
