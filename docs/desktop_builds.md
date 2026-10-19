# Desktop builds

These are portable x86-64 builds of LBA Model Renderer for Windows and Linux. Extract the ZIP, keeping `LBAModelRenderer.pck` beside the executable. Run `LBAModelRenderer.exe` on Windows or `LBAModelRenderer.x86_64` on Linux. On Linux, make the executable runnable if your archive tool did not preserve its permissions: `chmod +x LBAModelRenderer.x86_64`.

Choose your own LBA1, LBA2, or 1996 LBA2 demo installation folder in the app. Game archives are not included in these downloads.

**Export GLB** works within the app. **Export Blender** needs Blender installed on your computer and available as `blender` on your PATH. You can also set the `LBA_BLENDER` environment variable to the full path of the Blender executable. Blender is not bundled.

The builds use Godot 4.8.beta1 release templates. The Linux package was launched and checked in this build environment. The Windows executable was cross-exported from Linux; a native Windows run was not available here.

To make builds in the Godot editor, open **Project → Export**, select **Web**, **Linux**, or **Windows Desktop**, and click **Export Project**. The presets already have paths under `builds/`, and those directories are included in a fresh checkout. **Export All** exports all three. Install the matching Godot 4.8.beta1 export templates through **Editor → Manage Export Templates** if Godot asks for them. If an editor that was already open shows no presets after updating the project, close it and reopen this project's `project.godot`.

To reproduce the same exports from a terminal with matching templates installed:

```bash
godot --headless --path . --export-release Web
godot --headless --path . --export-release Linux
godot --headless --path . --export-release "Windows Desktop"
```

The Web preset writes `builds/web/index.html` and its companion files. The desktop presets write to `builds/linux-x86_64/` and `builds/windows-x86_64/`. Each executable must stay alongside the `.pck` from its own export. The downloadable desktop ZIPs at the root of `builds/` are packaged separately; Godot's **Export Project** does not create those ZIPs.
