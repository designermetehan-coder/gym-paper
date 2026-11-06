# Third-party notices

GYM Paper's own code is MIT licensed (see [LICENSE](LICENSE)). The following
third-party data, fonts and assets are used under their own licenses.

| Component | Used for | License |
|---|---|---|
| [Open Food Facts](https://world.openfoodfacts.org) | Packaged food data and barcode lookup | Database: [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/), images: [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) |
| [FatSecret Platform API](https://platform.fatsecret.com) | Optional food search (via `backend/supabase/functions/fatsecret`) | FatSecret Platform terms; requires your own API credentials |
| [free-exercise-db](https://github.com/yuhonas/free-exercise-db) | Exercise photos and instructions (`apps/ios/Balli/Resources/ExerciseMedia`, `apps/web/src/assets/ex`) | [The Unlicense](https://unlicense.org) (public domain) |
| [Geist](https://vercel.com/font) | Web app typeface | [SIL Open Font License 1.1](https://openfontlicense.org) |
| [Tabler Icons](https://tabler.io/icons) | Web app icons | MIT |
| Built-in food table | Offline food list | Compiled for this project from public food composition sources; values are approximate |

## Not included

**MoveKit 3D exercise animations.** The App Store build uses animations from
[MoveKit](https://movekit.com) under a commercial license that does not allow
redistribution. They are excluded from this repository and git-ignored
(`apps/ios/Balli/Resources/Motion`, `apps/ios/Balli/Resources/MotionWatch`).
Without them the apps fall back to the free-exercise-db photos. If you hold
your own MoveKit license, see [docs/ios.md](docs/ios.md#exercise-media).

Marketing screenshots in `apps/site` and `docs/assets` may show frames of these
animations. They are included only to illustrate the shipped app and are not
covered by this repository's MIT license.
