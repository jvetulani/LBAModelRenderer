class_name WebArchivePicker
extends Node

signal archives_ready(archives: Dictionary, folder_name: String)
signal failed(message: String)

var archives: Dictionary = {}
var _pending_archives: Dictionary = {}
var _callback: JavaScriptObject
var _folder_name := ""


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_callback = JavaScriptBridge.create_callback(_on_browser_files)
	JavaScriptBridge.get_interface("window").lbaArchivesCallback = _callback
	JavaScriptBridge.eval("""
		window.lbaPickArchives = function () {
			const input = document.createElement('input');
			input.type = 'file';
			input.webkitdirectory = true;
			input.directory = true;
			input.multiple = true;
			input.style.display = 'none';
			document.body.appendChild(input);
			input.oncancel = function () { input.remove(); };
			input.onchange = async function () {
				try {
					const wanted = ['BODY.HQR', 'ANIM.HQR', 'FILE3D.HQR', 'RESS.HQR'];
					const files = Array.from(input.files);
					if (!files.length) return;
					const folder = files[0].webkitRelativePath.split('/')[0];
					const selected = wanted.map(name => files.find(f =>
						f.name.toUpperCase() === name &&
						f.webkitRelativePath.split('/').length === 2));
					const missing = wanted.filter((name, index) => !selected[index]);
					if (missing.length) throw new Error('The selected folder is missing ' + missing.join(', '));
					for (let index = 0; index < wanted.length; index++) {
						const name = wanted[index];
						const file = selected[index];
						const bytes = new Uint8Array(await file.arrayBuffer());
						const chunks = [];
						for (let i = 0; i < bytes.length; i += 32768) {
							chunks.push(String.fromCharCode.apply(null, bytes.subarray(i, i + 32768)));
						}
						window.lbaArchivesCallback(JSON.stringify({name: name, folder: folder, data: btoa(chunks.join(''))}));
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
	_pending_archives.clear()
	_folder_name = ""
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
		_pending_archives.clear()
		failed.emit(str(message["error"]))
		return
	var name: String = message.get("name", "")
	if not name in ["BODY.HQR", "ANIM.HQR", "FILE3D.HQR", "RESS.HQR"]:
		failed.emit("Browser returned an unexpected archive")
		return
	_pending_archives[name] = Marshalls.base64_to_raw(message.get("data", ""))
	_folder_name = str(message.get("folder", ""))
	if _pending_archives.size() == 4:
		archives = _pending_archives.duplicate()
		_pending_archives.clear()
		archives_ready.emit(archives, _folder_name)
