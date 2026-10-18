# LBA Model Viewer

View and export character models and animations from **Little Big Adventure 1**, **Little Big Adventure 2**, and the **1996 LBA2 demo**. [Open the web viewer](https://jvetulani.github.io/LBAModelViewer/) or run the Godot project locally.

Choose your own game folder in the viewer. The project does not include game archives. The web viewer reads those files in your browser; it does not upload them. GLB and Blender export details are in [docs/export.md](docs/export.md).

To share a model from an HTTPS archive folder, enter the folder URL in the source field and load a BODY entry, then press **Copy link**. The link includes the selected BODY entry and animation. You can also use `?link=<encoded-folder-url>&body=4&anim=23` or `/link=<encoded-folder-url>?body=4&anim=23`. The folder must serve `BODY.HQR`, `ANIM.HQR`, and `RESS.HQR` directly, with browser cross-origin access enabled; `FILE3D.HQR` is optional. Local folders cannot be shared as links.

The preview defaults to **Soft dither**, which follows each model through animation and fades to smooth shading when the pattern becomes too fine to display. **Strong dither**, **Modern smooth**, and **Dither off** remain available in the shading menu. The interface uses the [Short Stack font](assets/ui/fonts/OFL.txt) under the SIL Open Font License.

## Help improve it

[Report a bug](https://github.com/jvetulani/LBAModelViewer/issues/new/choose) with the game version, BODY entry number, animation number or frame, and a screenshot when useful. Please do not attach copyrighted game archives. Code and documentation changes are welcome as [pull requests](https://github.com/jvetulani/LBAModelViewer/pulls). The viewer's local checks are described in [docs/validation.md](docs/validation.md).
