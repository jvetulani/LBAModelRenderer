# URLs and game files

The web renderer can fetch game archives from a normal HTTP or HTTPS folder. Put the archive files at the folder root, then enter its URL in the source field. **Copy link** includes the selected BODY entry and action. **Copy embed** makes a control-free link for an iframe. The desktop build opens a local game folder instead.

| Game | Required files in that folder |
| --- | --- |
| LBA1 | `BODY.HQR`, `ANIM.HQR`, `RESS.HQR`, `FILE3D.HQR` |
| LBA2 retail | `BODY.HQR`, `ANIM.HQR`, `RESS.HQR` |
| LBA2 1996 demo | `BODY.HQR`, `ANIM.HQR`, `RESS.HQR`, `FILE3D.HQR` |

`FILE3D.HQR` supplies the BODY-to-action associations and names for LBA1 and the demo. Retail LBA2 has its own association data in `RESS.HQR`. All three need `BODY.HQR` for geometry, `ANIM.HQR` for actions, and `RESS.HQR` for the palette and textures. Keep filenames and contents unchanged; no other game files are needed for model preview and export. The renderer does not bundle the archives or upload locally selected files.

## Link parameters

Use the query form below, replacing the example folder with your own URL. The folder URL is URL-encoded by **Copy link** and **Copy embed**.

```text
https://jvetulani.github.io/LBAModelRenderer/?link=https%3A%2F%2Fexample.com%2Flba2%2F&body=4&anim=23
```

| Parameter | Meaning |
| --- | --- |
| `link` | HTTP or HTTPS folder serving the HQR files directly. `/link=<encoded-folder-url>` is also accepted. |
| `body` | Zero-based `BODY.HQR` entry. Defaults to `0`. |
| `anim` | `ANIM.HQR` entry to select. If omitted, the first associated action is selected. |
| `embed=1` | Hide the controls and display platform. `ui=0` is an alias. |
| `transparent=1` | Request a transparent background for compositing over a host page. Use with `embed=1`. Browser/WebGL support needs checking on the target browser. |

For an iframe, set its `src` to a copied embed link; append `&transparent=1` if you want the host page to show behind the model:

```html
<iframe src="https://jvetulani.github.io/LBAModelRenderer/?link=https%3A%2F%2Fexample.com%2Flba2%2F&amp;body=4&amp;embed=1&amp;transparent=1" title="LBA model" width="640" height="480"></iframe>
```

The archive host must allow cross-origin browser requests from the renderer page (`Access-Control-Allow-Origin`). Use HTTPS archives with the hosted HTTPS renderer; browsers block insecure HTTP archives as [mixed content](https://www.w3.org/TR/mixed-content/). A link to a Google Drive folder or a page listing files is not a direct archive folder. Every requested `.HQR` URL must return the binary file itself. Sharing a link to a local folder cannot work for other visitors; host the required files first.
