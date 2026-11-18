# cvsafe_core

Shared Flutter code of CVSAFE, used by both clients:

| Client | Folder | Depends on |
| --- | --- | --- |
| Field app (Android, iOS) | `mobile/` | `cvsafe_core` |
| Web panel (Flutter Web) | `web_panel/` | `cvsafe_core` |

## Contents

| File | Purpose |
| --- | --- |
| `lib/src/api_client.dart` | `ApiClient` for the FastAPI backend (auth, site, incidents, analysis, users) |
| `lib/src/models.dart` | Data models mirroring the API responses |
| `lib/src/theme.dart` | Colours (`C`), text styles (`sans`, `mono`) and `buildTheme()` |
| `lib/src/widgets.dart` | State-free UI building blocks (`Panel`, `Pill`, `BigButton`, `NetImage`, ...) |
| `lib/src/formatters.dart` | Time formatting helpers |

Rules for this package:

- No app state and no state-management library: it must stay usable by both clients.
- Every API change is mirrored here once, then consumed by both apps.

```bash
flutter pub get
flutter analyze
flutter test
```
