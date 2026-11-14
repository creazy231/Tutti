# Listing backdrops and icon: the prompts

The three backdrops behind the CurseForge gallery and the animations (`bg-vault.jpg`, `bg-hall.jpg`,
`bg-camp.jpg`, next to this file) and the icon's source (`../icon-source.jpg`) were generated with
Google's Gemini image model from the prompts below. They show no people, no text, no interface and
no Blizzard art.

Each backdrop is the generated image (2752 x 1536) cropped to 16:9 around its middle, scaled to
1920 x 1080 with Lanczos, blurred with a Gaussian of 14 px (calm behind the window, yet the arches,
the gold, the light shaft and the campfire still read) and saved as a JPEG at quality 92,
progressive. The sharp originals are not in the repository.

`tools/make_listing.py` and `tools/make_gifs.py` copy the backdrops their shots name from here into
the render dir (see CLAUDE.md).

## bg-vault.jpg: the treasure vault

```text
A wide, cinematic digital matte painting for a website background: an ancient underground treasure vault deep inside a mountain, late at night.

Scene: heavy vaulted stone arches and thick pillars recede into darkness. On the stone floor in the lower middle of the frame: low heaps of gold coins, an iron-bound wooden treasure chest with its lid half open, a few goblets, a small round shield leaning against a pillar, scattered gemstones catching the light. Two or three iron wall torches give the only light.

Light and mood: calm, quiet and still, the treasure waiting. Warm amber and orange torchlight in soft pools, everything else falling off into deep brown-black shadow. Low contrast, no blown-out highlights, no strong rim lights. Overall a dark image: most of the frame is in shadow; the brightest areas are soft golden glows. A light dust haze in the air.

Style: painterly high-fantasy concept art, soft brushwork, gentle depth of field, the far background slightly out of focus. An original setting, not resembling any existing video game, film or famous place.

Composition: 16:9 landscape, eye level. The treasure and the light spread loosely across the lower middle; the left and right thirds are calm, darker stonework that can sit behind text and a window. No single object dominates.

Strictly exclude: people, characters, creatures, skeletons, faces, statues of figures, any text, letters, runes, inscriptions, numbers, symbols, emblems, logos, heraldic banners, user interface elements, frames, borders, watermarks, signatures.
```

## bg-hall.jpg: the ruined hall

```text
A wide, cinematic digital matte painting for a website background: a ruined dungeon hall at dusk.

Scene: a long hall of tall, weathered stone columns. Part of the vaulted ceiling has collapsed, and soft deep-blue twilight falls through the opening in a hazy shaft of light. At the far end, on a low stone dais, stands a single closed treasure chest with brass fittings, lit by two small iron braziers with low warm flames. Broken flagstones, a little rubble, some ivy and moss on the stones.

Light and mood: calm and still, the quiet moment after a fight, before the loot is shared. A palette of deep slate blue, teal and charcoal shadows, with small warm amber accents from the braziers and the chest. Low contrast, no bright highlights, overall dark: most of the frame is in soft shadow. Floating dust in the shaft of light.

Style: painterly high-fantasy concept art, soft brushwork, atmospheric perspective, gentle depth of field. An original setting, not resembling any existing video game, film or famous place.

Composition: 16:9 landscape, eye level, one-point perspective down the hall with the chest small near the center. The left and right thirds are calm, dark columns that can sit behind text and a window.

Strictly exclude: people, characters, creatures, skeletons, faces, statues of figures, any text, letters, runes, inscriptions, numbers, symbols, emblems, logos, heraldic banners, user interface elements, frames, borders, watermarks, signatures.
```

## bg-camp.jpg: the camp at dusk

```text
A wide, cinematic digital matte painting for a website background: an adventurers' camp at dusk in a quiet valley below old ruins.

Scene: a small campfire with low flames, slightly below the center; beside it an open wooden chest with a few gold coins and a sword resting against it, bedrolls and travel packs, two canvas tents in shadow. Behind, the silhouettes of a broken stone tower and pine trees; far away, layered mountains under a fading twilight sky of deep violet and dusky orange, with the first stars.

Light and mood: calm, warm and peaceful, the rest after the dungeon. Warm firelight in a soft pool, the rest in cool violet-blue shadow. Low contrast, no bright highlights, overall dark.

Style: painterly high-fantasy concept art, soft brushwork, atmospheric haze, gentle depth of field. An original setting, not resembling any existing video game, film or famous place.

Composition: 16:9 landscape, eye level; the left and right thirds are calm, dark trees and ground that can sit behind text and a window.

Strictly exclude: people, characters, creatures, animals, faces, any text, letters, runes, inscriptions, numbers, symbols, emblems, logos, flags with heraldry, user interface elements, frames, borders, watermarks, signatures.
```

## icon-source.jpg: the icon

The icon (`../icon.png`, 400 x 400) was made from this image.

```text
A square app icon for a software add-on, 1:1, flat and minimal: one glowing orange line symbol on a dark background, like a soft neon sign.

The symbol: a single die seen straight from the front. A rounded-square outline with a thick, even stroke (the stroke is about one tenth of the die's width) and soft rounded corners (corner radius about a quarter of the die's width). Inside it, five solid round pips arranged like the face of a die showing five: one near each corner and one in the exact center. Each pip is about one fifth of the die's width, with clear dark space between the pips and the outline, so the symbol stays readable at 64 pixels.

Colour and light: the outline and the pips are one flat, bright, warm orange (#FF7D0A), with no darker rim and no highlight on the shapes. A soft, wide, warm orange glow spreads around the symbol and fades gently into the background. Background: a flat near-black charcoal (#141414) with a faint warm haze behind the symbol and a slightly darker vignette toward the corners.

Composition: perfectly centered and symmetrical; the die is about 50 percent of the canvas width; straight-on, no perspective, not a 3D cube, no bevel, no texture.

Strictly exclude: text, letters, numbers, extra symbols, other dice, sparkles, game icons, logos, a rounded tile or plate around the icon, borders, watermarks, reflections, a floor or shadow below.
```
