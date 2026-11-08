# Logo-Bilder

PNG-Fassungen des Logos für Willkommen und Heute (FR-0207, FR-0209). Quelle sind die SVG in `branding/svg/`; erzeugt mit rsvg-convert 2.63.3 (`brew install librsvg`), vom Repository-Stamm aus:

```sh
rsvg-convert -w 537 branding/svg/ramuri-logo-stacked-on-dark.svg -o app/assets/brand/ramuri-logo-stacked-on-dark.png
rsvg-convert -w 582 branding/svg/ramuri-logo-horizontal-on-light.svg -o app/assets/brand/ramuri-logo-horizontal-on-light.png
rsvg-convert -w 582 branding/svg/ramuri-logo-horizontal-on-dark.svg -o app/assets/brand/ramuri-logo-horizontal-on-dark.png
```

Breiten: gestapelt 537 px (4-fach der SVG-Breite 134 px, angezeigt 168 dp), horizontal 582 px (2-fach, angezeigt 110 dp). Kein neues Paket; Flutter zeigt die PNG mit `Image.asset`.
