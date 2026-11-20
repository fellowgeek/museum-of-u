# Optional local models

The gallery ships with CC0 exhibits and native Godot door and flashlight scenes. You can switch individual slots to the following artist models for personal play. Each listing was free at acquisition. Check the current listing and terms before downloading. Keep your downloaded sources outside Godot’s import tree and keep converted models in the Git-ignored `local_models/` folder. The public export presets exclude this folder. [Blendkit licenses](https://www.blendkit.com/docs/licenses/) · [Game licensing FAQ](https://www.blendkit.com/docs/licenses/licensing-faq/)

## Sculpture and plant slots

Open the linked listing in the Blendkit Blender add-on and append the model to an empty Blender scene. Set units to meters, apply transforms, center the model on XY, and ground its lowest visible point at Z=0. Scale uniformly to the listed height. Use glTF-compatible Principled materials and embed textures. For collision, add a simplified convex mesh named with the Godot `-convcolonly` suffix. Select both objects and export glTF 2.0 as a binary GLB with selected objects and +Y up. Save under `local_models/` using the exact filename below. Open the Godot editor, allow import to finish, then start a new visit. Remove the GLB to restore the bundled exhibit.

| Listing | Filename | Height (m) |
| --- | --- | ---: |
| [Alba Ceramic Sculptural Objects](https://www.blendkit.com/asset-gallery-detail/fdfec0a5-4ec5-44b5-a729-5c8e41e0964e/) | `alba_ceramics.glb` | 0.65 |
| [Antique Bathing Goddess Statue White](https://www.blendkit.com/asset-gallery-detail/58a9f366-ba09-4203-bf87-a0b712bda37b/) | `bathing_goddess.glb` | 1.90 |
| [Calathea plant](https://www.blendkit.com/asset-gallery-detail/e6ddf713-19bd-4fff-9ac8-f157509f4858/) | `calathea_plant.glb` | 1.10 |
| [Canova naiad statue](https://www.blendkit.com/asset-gallery-detail/d4372df8-6b26-4b33-b7d7-22861b4bfc8d/) | `canova_naiad.glb` | 0.78 |
| [Buddha Concrete Statue](https://www.blendkit.com/asset-gallery-detail/1bc5075c-83c1-49cd-8280-12ad9e43798f/) | `concrete_buddha.glb` | 1.30 |
| [Expressive Female Statue Aged Stone](https://www.blendkit.com/asset-gallery-detail/f0d5cadb-7a1e-463a-bb19-3c7c90c657cb/) | `expressive_stone.glb` | 0.70 |
| [Female Bust Sculpture](https://www.blendkit.com/asset-gallery-detail/73ab4b39-db8d-4684-87ad-c300335c6f46/) | `female_bust.glb` | 1.05 |
| [Guadeloupe Woman Wood Statue](https://www.blendkit.com/asset-gallery-detail/951a04d9-2351-4c47-b1ef-c29617dabb42/) | `guadeloupe_wood.glb` | 1.30 |
| [statue of Vs Jungling](https://www.blendkit.com/asset-gallery-detail/bf049fb2-dc12-48bf-8663-2ecd6e3a31f5/) | `jungling.glb` | 1.85 |
| [Monstera plant](https://www.blendkit.com/asset-gallery-detail/65ea3e91-b091-4f2c-97a4-d118c594a537/) | `monstera_plant.glb` | 1.50 |
| [Sad woman statue](https://www.blendkit.com/asset-gallery-detail/32a52ea4-2997-4f16-9ffe-5d3bfb1479e3/) | `sad_woman.glb` | 1.80 |
| [statue of Vs La Nymphe Salmacis](https://www.blendkit.com/asset-gallery-detail/e809ab4d-2b70-4967-b015-d1bc0bd4859b/) | `salmacis.glb` | 1.28 |
| [Stone Seated Female Sculpture](https://www.blendkit.com/asset-gallery-detail/af5c313d-ad55-46bd-b29d-01405bc312b2/) | `seated_sculpture.glb` | 1.20 |
| [Taihu Stone Sculpture](https://www.blendkit.com/asset-gallery-detail/357a30f1-4fc6-46cf-8bff-ee74d083fdee/) | `taihu_stone.glb` | 1.60 |
| [Tiki God Pineapple Top Statue Stone](https://www.blendkit.com/asset-gallery-detail/019a73b5-eebe-4854-a34c-1f1511d90062/) | `tiki_stone.glb` | 1.38 |
| [Venus de Milo sculpture](https://www.blendkit.com/asset-gallery-detail/235fab8c-fda5-4e81-9397-f093a311753e/) | `venus_statue.glb` | 2.10 |

## Animated door and VR flashlight

Download the [Animated Interior Door by John Martin](https://www.blenderkit.com/asset-gallery-detail/5b017692-720c-4d46-942a-3e69bb30d817/) or the [Flashlight by Vadim Gubey](https://www.blendkit.com/asset-gallery-detail/dce17120-9b27-4f04-961d-bb87359e8272/). Use the original Blender file with its original object names and packed textures. From the project root, create `third_party_assets/.gdignore` before adding the source files there. Save the respective files as `third_party_assets/blendkit/interior_door/source.blend` and `third_party_assets/blendkit/flashlight/source.blend`. Run the matching converter with Blender 5.2:

```sh
blender --background --disable-autoexec --python-exit-code 1 --python scripts/tools/export_interior_door.py
blender --background --disable-autoexec --python-exit-code 1 --python scripts/tools/export_vr_flashlight.py
```

The converters write `local_models/door.glb` and `local_models/flashlight.glb`. The door converter samples the hinge and moving hardware and fits the service opening. The flashlight converter aligns the lens along Godot’s negative Z axis. After editor import, restart the visit. Door collision and the tracked flashlight mount are supplied by the game.
