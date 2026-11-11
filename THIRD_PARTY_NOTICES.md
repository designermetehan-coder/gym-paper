# Third-party notices

| What | Where | License / terms |
|---|---|---|
| Exercise photos + how-to texts | `ios/GymPaper/Resources/ExerciseMedia` | [free-exercise-db](https://github.com/yuhonas/free-exercise-db) — The Unlicense (public domain) |
| Product search & barcodes (online) | `GymPaperKit/FoodClients.swift` | [Open Food Facts](https://world.openfoodfacts.org) — data under ODbL; attribution shown in the app |
| Food search proxy (optional) | your own Supabase function | [FatSecret Platform API](https://platform.fatsecret.com) — requires your own API account and the "Powered by FatSecret" attribution |
| Built-in food list (sample) | `GymPaperKit/Resources/foods.json` | ~300-item sample of nutrient averages compiled by the author from public references (USDA FoodData Central, public domain). The App Store build's full list is not included. |
| Muscle map polygons | `ios/GymPaper/Design/MuscleMap.swift` | [react-body-highlighter](https://github.com/giavinh79/react-body-highlighter) — MIT, © 2021 Giavinh Lam |
| Icons | SF Symbols | Apple — usable in apps for Apple platforms only |
| Font | SF Pro (system font) | Apple — not bundled |

## Not included: MoveKit

The App Store version of GYM Paper uses licensed 3D exercise animations from **MoveKit**.
They are **not** part of this repository and may not be redistributed. Without them the app
automatically falls back to the free-exercise-db photos or a neutral silhouette.
If you own a MoveKit license, drop the files into `ios/GymPaper/Resources/Motion` (`mk-<slug>.mp4/.jpg`),
`ios/GymPaper/Resources/MotionWatch` and add `mk-map.json`; they're git-ignored.

## react-body-highlighter — MIT License

Copyright (c) 2021 Giavinh Lam

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and
to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions
of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
