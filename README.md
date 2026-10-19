# LBA Model Renderer

View and export character models and animations from **Little Big Adventure 1**, **Little Big Adventure 2**, and the **1996 LBA2 demo**. [Open the web viewer](https://jvetulani.github.io/LBAModelRenderer/) or run the Godot project locally.

Shareable character sheets: [LBA1](showcase/lba1-characters.png) and [LBA2](showcase/lba2-characters.png). Each shows 20 selected BODY entries rendered in the viewer, labeled by entry number.

Choose your own game folder in the viewer. The project does not include game archives. The web viewer reads those files in your browser; it does not upload them. GLB and Blender export details are in [docs/export.md](docs/export.md).

To share a model from an HTTPS archive folder, enter the folder URL in the source field and load a BODY entry, then press **Copy link**. **Copy embed** makes the same link with `embed=1`, which hides the controls and display platform. Local folders cannot be shared as links. See [URL and archive setup](docs/urls-and-game-files.md) for all parameters, iframe examples, and the files each game needs.

For LBA2 models, press **Find…** beside the BODY number to search by character, object, or entry number. Retail labels are adapted from [LBA File Information's BODY catalog](https://lbafileinfo.kaziq.net/index.php/LBA2:Body.hqr) by Battler (CC BY-SA), with character spellings checked against the [LBA Wiki](https://lba.fandom.com/wiki/Category:LBA2_Characters). Demo labels are currently limited to identified characters. The game archives contain numbered models, not embedded model names. Search treats `Zoe` and `Zoé` alike.

The preview defaults to **Soft dither**, which follows each model through animation, uses the source palette light range, and fades to smooth shading when the pattern becomes too fine to display. **Dither off** shows the corresponding palette bands, while **Modern smooth** uses per-pixel lighting. The fixed light direction and scanline pattern remain approximate. A toggleable ground grid scrolls with animation root movement and fades away from the model. The interface uses the [Short Stack font](assets/ui/fonts/OFL.txt) under the SIL Open Font License.

## Help improve it

[Report a bug](https://github.com/jvetulani/LBAModelRenderer/issues/new/choose) with the game version, BODY entry number, animation number or frame, and a screenshot when useful. Please do not attach copyrighted game archives. Code and documentation changes are welcome as [pull requests](https://github.com/jvetulani/LBAModelRenderer/pulls). The viewer's local checks are described in [docs/validation.md](docs/validation.md).
