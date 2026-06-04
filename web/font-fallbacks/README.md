CanvasKit fallback fonts served from the app origin.

Flutter Web's CanvasKit renderer asks for fallback fonts relative to
`fontFallbackBaseUrl`. The category emoji depend on Noto Color Emoji, so these
files are kept local to avoid blank glyphs when `fonts.gstatic.com` is
unavailable or blocked.

Paths mirror Flutter engine fallback URLs:

- `roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2`
- `notocoloremoji/v32/Yq6P-KqIXTD0t4D9z1ESnKM3-HpFabsE4tq3luCC7p-aXxcn.*.woff2`
