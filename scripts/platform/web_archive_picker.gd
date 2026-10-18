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
		window.lbaReadArchive = async function (name, folder, buffer) {
			const bytes = new Uint8Array(buffer);
			const chunks = [];
			for (let i = 0; i < bytes.length; i += 32768) {
				chunks.push(String.fromCharCode.apply(null, bytes.subarray(i, i + 32768)));
			}
			window.lbaArchivesCallback(JSON.stringify({name: name, folder: folder, data: btoa(chunks.join(''))}));
		};
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
					const wanted = ['BODY.HQR', 'ANIM.HQR', 'RESS.HQR'];
					const files = Array.from(input.files);
					if (!files.length) return;
					const folder = files[0].webkitRelativePath.split('/')[0];
					const selected = wanted.map(name => files.find(f =>
						f.name.toUpperCase() === name &&
						f.webkitRelativePath.split('/').length === 2));
					const missing = wanted.filter((name, index) => !selected[index]);
					if (missing.length) throw new Error('The selected folder is missing ' + missing.join(', '));
					for (let index = 0; index < wanted.length; index++) {
						await window.lbaReadArchive(wanted[index], folder, await selected[index].arrayBuffer());
					}
					const file3d = files.find(f => f.name.toUpperCase() === 'FILE3D.HQR' && f.webkitRelativePath.split('/').length === 2);
					if (file3d) await window.lbaReadArchive('FILE3D.HQR', folder, await file3d.arrayBuffer());
					window.lbaArchivesCallback(JSON.stringify({complete: true, folder: folder}));
				} catch (error) {
					window.lbaArchivesCallback(JSON.stringify({error: String(error)}));
				} finally {
					input.remove();
				}
			};
			input.click();
		};
		window.lbaFetchArchives = async function (path) {
			try {
				const base = new URL(path.endsWith('/') ? path : path + '/');
				if (!['http:', 'https:'].includes(base.protocol)) throw new Error('Use an HTTP or HTTPS folder URL');
				for (const name of ['BODY.HQR', 'ANIM.HQR', 'RESS.HQR']) {
					const response = await fetch(new URL(name, base));
					if (!response.ok) throw new Error(name + ': HTTP ' + response.status);
					await window.lbaReadArchive(name, path, await response.arrayBuffer());
				}
				const optional = await fetch(new URL('FILE3D.HQR', base));
				if (optional.ok) await window.lbaReadArchive('FILE3D.HQR', path, await optional.arrayBuffer());
				window.lbaArchivesCallback(JSON.stringify({complete: true, folder: path}));
			} catch (error) {
				window.lbaArchivesCallback(JSON.stringify({error: String(error)}));
			}
		};
	""")


func pick() -> void:
	if not OS.has_feature("web"):
		failed.emit("Browser archive picker is only available on the web build")
		return
	_pending_archives.clear()
	_folder_name = ""
	JavaScriptBridge.eval("window.lbaPickArchives()")


func load_url(url: String) -> void:
	if not OS.has_feature("web"):
		failed.emit("URL loading is only available on the web build")
		return
	_pending_archives.clear()
	_folder_name = url
	JavaScriptBridge.eval("window.lbaFetchArchives(%s)" % JSON.stringify(url))


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
	if message.get("complete", false):
		for required in ["BODY.HQR", "ANIM.HQR", "RESS.HQR"]:
			if not _pending_archives.has(required):
				failed.emit("Browser source is missing %s" % required)
				return
		archives = _pending_archives.duplicate()
		_pending_archives.clear()
		archives_ready.emit(archives, _folder_name)
		return
	var name: String = message.get("name", "")
	if not name in ["BODY.HQR", "ANIM.HQR", "FILE3D.HQR", "RESS.HQR"]:
		failed.emit("Browser returned an unexpected archive")
		return
	_pending_archives[name] = Marshalls.base64_to_raw(message.get("data", ""))
	_folder_name = str(message.get("folder", ""))
