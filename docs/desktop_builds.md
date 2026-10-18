# Desktop builds

These are portable x86-64 builds of LBA Model Renderer for Windows and Linux. Extract the ZIP, keeping `LBAModelRenderer.pck` beside the executable. Run `LBAModelRenderer.exe` on Windows or `LBAModelRenderer.x86_64` on Linux. On Linux, make the executable runnable if your archive tool did not preserve its permissions: `chmod +x LBAModelRenderer.x86_64`.

Choose your own LBA1, LBA2, or 1996 LBA2 demo installation folder in the app. Game archives are not included in these downloads.

**Export GLB** works within the app. **Export Blender** needs Blender installed on your computer and available as `blender` on your PATH. You can also set the `LBA_BLENDER` environment variable to the full path of the Blender executable. Blender is not bundled.

The builds use Godot 4.8.beta1 release templates. The Linux package was launched and checked in this build environment. The Windows executable was cross-exported from Linux; a native Windows run was not available here.

To reproduce a build with matching Godot export templates installed:

```bash
godot --headless --path . --export-release Linux builds/linux-x86_64/LBAModelRenderer.x86_64
godot --headless --path . --export-release "Windows Desktop" builds/windows-x86_64/LBAModelRenderer.exe
```

Each executable must stay alongside the `.pck` from its own export.
