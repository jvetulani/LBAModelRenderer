class_name WebArchivePicker
extends Node

signal archives_ready(archives: Dictionary)
signal failed(message: String)

var archives: Dictionary = {}
var _callback: JavaScriptObject


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_callback = JavaScriptBridge.create_callback(_on_browser_files)
	JavaScriptBridge.get_interface("window").lbaArchivesCallback = _callback
	JavaScriptBridge.eval("""
		window.lbaPickArchives = function () {
			const input = document.createElement('input');
			input.type = 'file';
			input.multiple = true;
			input.accept = '.hqr,.HQR';
			input.style.display = 'none';
			document.body.appendChild(input);
			input.onchange = async function () {
				try {
					const wanted = ['BODY.HQR', 'ANIM.HQR', 'FILE3D.HQR', 'RESS.HQR'];
					const files = Array.from(input.files);
					for (const name of wanted) {
						const file = files.find(f => f.name.toUpperCase() === name);
						if (!file) throw new Error('Select BODY.HQR, ANIM.HQR, FILE3D.HQR and RESS.HQR together. Missing ' + name);
						const bytes = new Uint8Array(await file.arrayBuffer());
						const chunks = [];
						for (let i = 0; i < bytes.length; i += 32768) {
							chunks.push(String.fromCharCode.apply(null, bytes.subarray(i, i + 32768)));
						}
						window.lbaArchivesCallback(JSON.stringify({name: name, data: btoa(chunks.join(''))}));
					}
				} catch (error) {
					window.lbaArchivesCallback(JSON.stringify({error: String(error)}));
				} finally {
					input.remove();
				}
			};
			input.click();
		};
	""")


func pick() -> void:
	if not OS.has_feature("web"):
		failed.emit("Browser archive picker is only available on the web build")
		return
	archives.clear()
	JavaScriptBridge.eval("window.lbaPickArchives()")


func _on_browser_files(arguments: Array) -> void:
	if arguments.is_empty():
		failed.emit("Browser did not return the archive files")
		return
	var message = JSON.parse_string(str(arguments[0]))
	if not message is Dictionary:
		failed.emit("Browser returned an invalid archive result")
		return
	if message.has("error"):
		archives.clear()
		failed.emit(str(message["error"]))
		return
	var name: String = message.get("name", "")
	if not name in ["BODY.HQR", "ANIM.HQR", "FILE3D.HQR", "RESS.HQR"]:
		failed.emit("Browser returned an unexpected archive")
		return
	archives[name] = Marshalls.base64_to_raw(message.get("data", ""))
	if archives.size() == 4:
		archives_ready.emit(archives)
