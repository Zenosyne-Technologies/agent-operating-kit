# Self-hosted fonts

The docs site serves its own fonts so a visitor's browser makes no third-party request. Each file is the Latin
subset Google Fonts serves for the family, copied unmodified. `site/assets/site.css` declares them with relative
`url(fonts/...)`. Source URLs are written without their scheme so the site's no-remote-URL test applies to this
file as well; add the https scheme to fetch one.

| File | Family | Weights | Licence | Source |
|---|---|---|---|---|
| `montserrat-latin-variable.woff2` | Montserrat (variable) | 400-700 | SIL OFL 1.1, `OFL-Montserrat.txt` | `fonts.gstatic.com/s/montserrat/v31/JTUSjIg1_i6t8kCHKm459WlhyyTh89Y.woff2` |
| `ibm-plex-mono-latin-400.woff2` | IBM Plex Mono | 400 | SIL OFL 1.1, `OFL-IBMPlexMono.txt` | `fonts.gstatic.com/s/ibmplexmono/v23/-F63fjptAgt5VM-kVkqdyU8n1i8q131nj-o.woff2` |
| `ibm-plex-mono-latin-500.woff2` | IBM Plex Mono | 500 | SIL OFL 1.1, `OFL-IBMPlexMono.txt` | `fonts.gstatic.com/s/ibmplexmono/v23/-F6qfjptAgt5VM-kVkqdyU8n3twJwlBFgsAXHNk.woff2` |
| `OFL-Montserrat.txt` | Montserrat licence | - | - | `raw.githubusercontent.com/JulietaUla/Montserrat/master/OFL.txt` |
| `OFL-IBMPlexMono.txt` | IBM Plex licence | - | - | `raw.githubusercontent.com/IBM/plex/master/LICENSE.txt` |

## sha256

The fonts are byte-identical to the download, and `scripts/test-build-docs.sh` checks these sums against both
`site/assets/fonts/` and the built `docs/assets/fonts/`.

```
6438d7b8ea9c7c3992d5e2fd2afdb1ff948570a3ef0bedae76247b51632960ba  montserrat-latin-variable.woff2
52de70091213c9eab340e2a7ac59e7b6b2b94e089bf69ef38479b22cfde4274c  ibm-plex-mono-latin-400.woff2
f17f51948d10b67d907393ccbac551912f2c2bd2c5af19be3aabe2f456f8fe54  ibm-plex-mono-latin-500.woff2
8b7141c03fa4f8d44e6345d5d4931709290f0f67875e452e95ac1fd3a027802e  OFL-Montserrat.txt
37784b44044a4ffd9256702b7c0982c37e5c8887ba90c6dca0479aea93dc898d  OFL-IBMPlexMono.txt
```

`OFL-IBMPlexMono.txt` arrived with CRLF line endings (sha256
`7e6b2818edbd8f6a01ae80641cc8f16a51080d08fb4e532be3a0b6f74adb07da`). The repo stores every `site/` text file with LF,
so the committed copy is the same text with LF endings, and the second sum above is that copy's. Its wording is
unchanged.

Only these open-licence files ship. Emprove's proprietary headline face is never copied here; Montserrat is the
documented fallback Emprove names for it.
