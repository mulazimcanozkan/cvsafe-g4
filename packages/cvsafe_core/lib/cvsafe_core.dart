/// Shared CVSAFE client code used by the field app (`mobile/`) and the web panel (`web_panel/`).
///
/// * [ApiClient] - thin client for the FastAPI backend
/// * data models mirroring the API responses ([Incident], [Camera], [UserInfo], ...)
/// * theme ([C], [buildTheme], [sans], [mono]) and small UI building blocks ([Panel], [Pill], ...)
/// * formatting helpers ([timeAgo], [clock], [dateTime])
library;

export 'src/api_client.dart';
export 'src/formatters.dart';
export 'src/models.dart';
export 'src/theme.dart';
export 'src/widgets.dart';
