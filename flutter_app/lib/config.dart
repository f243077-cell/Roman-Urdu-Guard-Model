/// Base URLs come from --dart-define at run time (see flutter_app/README.md).
///
/// GUARD_API_KEY is the key of your own local guard-api, passed in at run time for the playground.
/// It is never committed, and the app holds no LLM provider key of any kind.
class AppConfig {
  const AppConfig({required this.guardUrl, required this.demoUrl, required this.guardApiKey});

  /// A URL starting with '/' (the hosted demo: GUARD_URL=/guard, DEMO_URL=/demo) is resolved against the page,
  /// so the app calls its own origin and the deploy proxy adds the key on the server (no key in the build).
  factory AppConfig.fromEnvironment() => AppConfig(
        guardUrl: _absolute(const String.fromEnvironment('GUARD_URL', defaultValue: 'http://localhost:8001')),
        demoUrl: _absolute(const String.fromEnvironment('DEMO_URL', defaultValue: 'http://localhost:8002')),
        guardApiKey: const String.fromEnvironment('GUARD_API_KEY'),
      );

  /// A relative URL goes to the backend named by `?api=` (the GitHub Pages site, D61), else to this page's origin.
  static String _absolute(String url) {
    if (!url.startsWith('/')) return url;
    final api = _apiBase();
    return api != null ? '$api$url' : Uri.base.resolve(url).toString().replaceFirst(RegExp(r'/$'), '');
  }

  /// `?api=https://<name>.trycloudflare.com` (or `.lhr.life`): only these free-tunnel hosts over https are accepted,
  /// so a crafted link cannot send what a visitor types to some other server.
  static String? _apiBase() {
    final raw = Uri.base.queryParameters['api'];
    final u = raw == null ? null : Uri.tryParse(raw);
    if (u == null || u.scheme != 'https') return null;
    final ok = u.host.endsWith('.trycloudflare.com') || u.host.endsWith('.lhr.life');
    return ok ? 'https://${u.host}' : null;
  }

  final String guardUrl;
  final String demoUrl;
  final String guardApiKey;
}
