class_name WebArchivePicker
extends Node

signal archives_ready(archives: Dictionary, folder_name: String)
signal failed(message: String)
signal share_finished(message: String)

var archives: Dictionary = {}
var _pending_archives: Dictionary = {}
var _callback: JavaScriptObject
var _share_callback: JavaScriptObject
var _folder_name := ""


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_callback = JavaScriptBridge.create_callback(_on_browser_files)
	JavaScriptBridge.get_interface("window").lbaArchivesCallback = _callback
	_share_callback = JavaScriptBridge.create_callback(_on_share_result)
	JavaScriptBridge.get_interface("window").lbaShareCallback = _share_callback
	JavaScriptBridge.eval("""
		window.lbaCopyLink = async function (source, body, animation, embed) {
			const link = new URL(window.location.href);
			link.pathname = link.pathname.replace(/link=[^/]+\\/?$/, '');
			link.search = '';
			link.hash = '';
			link.searchParams.set('link', source);
			link.searchParams.set('body', String(body));
			if (animation >= 0) link.searchParams.set('anim', String(animation));
			if (embed) link.searchParams.set('embed', '1');
			try {
				await navigator.clipboard.writeText(link.href);
				window.lbaShareCallback('Link copied to clipboard.');
			} catch (error) {
				window.lbaShareCallback('Copy this link: ' + link.href);
			}
		};
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
					const files = Array.from(input.files);
					if (!files.length) return;
					const root = files[0].webkitRelativePath.split('/')[0];
					const aitdBody = files.find(f => f.name.toUpperCase() === 'LISTBODY.PAK');
					if (aitdBody) {
						const path = aitdBody.webkitRelativePath.split('/').slice(0, -1).join('/');
						const folderFiles = files.filter(f => f.webkitRelativePath.split('/').slice(0, -1).join('/') === path);
						const required = ['LISTBODY.PAK', 'LISTANIM.PAK'];
						const optional = ['ITD_RESS.PAK', 'CAMERA00.PAK', 'OBJETS.ITD', 'LISTLIFE.PAK'];
						for (const name of required) {
							const file = folderFiles.find(f => f.name.toUpperCase() === name);
							if (!file) throw new Error('The selected AITD folder is missing ' + name);
							await window.lbaReadArchive(name, path, await file.arrayBuffer());
						}
						for (const name of optional) {
							const file = folderFiles.find(f => f.name.toUpperCase() === name);
							if (file) await window.lbaReadArchive(name, path, await file.arrayBuffer());
						}
						const game = /(?:ALONE|AITD)3/i.test(path) ? 'AITD3' : (/(?:ALONE|AITD)2/i.test(path) ? 'AITD2' : 'AITD1');
						window.lbaArchivesCallback(JSON.stringify({complete: true, folder: path, game: game}));
						return;
					}
					const wanted = ['BODY.HQR', 'ANIM.HQR', 'RESS.HQR'];
					const folder = root;
					const selected = wanted.map(name => files.find(f =>
						f.name.toUpperCase() === name &&
						f.webkitRelativePath.split('/').length === 2));
					const missing = wanted.filter((name, index) => !selected[index]);
					if (missing.length) throw new Error('The selected folder is missing ' + missing.join(', '));
					for (let index = 0; index < wanted.length; index++) {
						await window.lbaReadArchive(wanted[index], folder, await selected[index].arrayBuffer());
					}
					for (const name of ['FILE3D.HQR', 'INVOBJ.HQR', 'OBJFIX.HQR']) {
						const optional = files.find(f => f.name.toUpperCase() === name && f.webkitRelativePath.split('/').length === 2);
						if (optional) await window.lbaReadArchive(name, folder, await optional.arrayBuffer());
					}
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
				if (base.hostname === 'drive.google.com') {
					throw new Error('Google Drive folder links need a download proxy; Drive does not serve HQR files as a normal web folder.');
				}
				for (const name of ['BODY.HQR', 'ANIM.HQR', 'RESS.HQR']) {
					const response = await fetch(new URL(name, base));
					if (!response.ok) throw new Error(name + ': HTTP ' + response.status);
					await window.lbaReadArchive(name, path, await response.arrayBuffer());
				}
			// Retail LBA2 does not have FILE3D.HQR. A missing optional file may
			// reject at the CORS layer instead of returning an HTTP 404.
			for (const name of ['FILE3D.HQR', 'INVOBJ.HQR', 'OBJFIX.HQR']) {
				try {
					const optional = await fetch(new URL(name, base));
					if (optional.ok) await window.lbaReadArchive(name, path, await optional.arrayBuffer());
				} catch (_) {}
			}
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


func copy_deep_link(source: String, body_index: int, animation_index: int, embed: bool = false) -> void:
	if not OS.has_feature("web"):
		share_finished.emit("Share links are only available on the web build.")
		return
	JavaScriptBridge.eval("window.lbaCopyLink(%s, %d, %d, %s)" % [JSON.stringify(source), body_index, animation_index, "true" if embed else "false"])


func _on_share_result(arguments: Array) -> void:
	if not arguments.is_empty():
		share_finished.emit(str(arguments[0]))


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
		var aitd := str(message.get("game", "")).begins_with("AITD")
		for required in (["LISTBODY.PAK", "LISTANIM.PAK"] if aitd else ["BODY.HQR", "ANIM.HQR", "RESS.HQR"]):
			if not _pending_archives.has(required):
				failed.emit("Browser source is missing %s" % required)
				return
		archives = _pending_archives.duplicate()
		if aitd:
			archives["_aitd_game"] = str(message["game"])
		_pending_archives.clear()
		archives_ready.emit(archives, _folder_name)
		return
	var name: String = message.get("name", "")
	if not name in ["BODY.HQR", "ANIM.HQR", "FILE3D.HQR", "INVOBJ.HQR", "OBJFIX.HQR", "RESS.HQR", "LISTBODY.PAK", "LISTANIM.PAK", "ITD_RESS.PAK", "CAMERA00.PAK", "OBJETS.ITD", "LISTLIFE.PAK"]:
		failed.emit("Browser returned an unexpected archive")
		return
	_pending_archives[name] = Marshalls.base64_to_raw(message.get("data", ""))
	_folder_name = str(message.get("folder", ""))
