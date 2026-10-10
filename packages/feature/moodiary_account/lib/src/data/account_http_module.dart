import 'package:injectable/injectable.dart';
import 'package:moodiary_http/moodiary_http.dart';

@module
abstract class AccountHttpModule {
  /// Never forward passwords or tokens to a redirected account endpoint.
  @Named('selumnAccount')
  @lazySingleton
  IHttpClient accountHttpClient() => RustHttpClient(maxRedirects: 0);
}
