# LBA Model Viewer

View and export character models and animations from **Little Big Adventure 1**, **Little Big Adventure 2**, and the **1996 LBA2 demo**. [Open the web viewer](https://jvetulani.github.io/LBAModelViewer/) or run the Godot project locally.

Choose your own game folder in the viewer. The project does not include game archives. The web viewer reads those files in your browser; it does not upload them. GLB and Blender export details are in [docs/export.md](docs/export.md).

The preview defaults to **Soft dither**, which follows each model through animation and fades to smooth shading when the pattern becomes too fine to display. **Strong dither**, **Modern smooth**, and **Dither off** remain available in the shading menu. The interface uses the [Short Stack font](assets/ui/fonts/OFL.txt) under the SIL Open Font License.

## Help improve it

[Report a bug](https://github.com/jvetulani/LBAModelViewer/issues/new/choose) with the game version, BODY entry number, animation number or frame, and a screenshot when useful. Please do not attach copyrighted game archives. Code and documentation changes are welcome as [pull requests](https://github.com/jvetulani/LBAModelViewer/pulls). The viewer's local checks are described in [docs/validation.md](docs/validation.md).
