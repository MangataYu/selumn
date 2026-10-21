# Mobile: the composition root

Composition-root details for dependency injection, bootstrap, and app mounting.

## Dependency injection

- Put binding annotations on implementation classes (`@Singleton(as:)`, `@LazySingleton(as:)`, `@Injectable(as:)`).
- `lib/app/di/di.dart` mounts injectable micro-package modules through `externalPackageModulesBefore`. Keep storage first; its factories use `preResolve`, and `MmkvKVStorage.create(ISecureKVStorage)` enforces secure-storage initialization before KV migration.
- Keep one `configureDependencies` entry point in this app, using injectable's default initializer and generation scope to avoid duplicate registration. The desktop app owns a separate composition root; neither app imports the other's root.
- Use `AppModule` for bindings needing app behavior: the HTTP error toast and database path. Repositories stay lazy so they can resolve these app-provided dependencies after package registration.
- Startup belongs to `lib/main.dart` and `lib/app/di/bootstrap.dart`, not `@PostConstruct`. Activate the selected sync provider after version migration, then start `AutoSyncWatcher`.
- After changing annotations, run `fvm dart tool/task.dart build-runner` from the repository root and include generated files. Production registrations stay generated; `activateSyncProvider()` deliberately manages the unnamed `IRemoteSyncBackend` through a session scope.
- Maintain `_assertRequiredBindings` when required services change.
- Import annotations from `package:injectable/injectable.dart` and declare that dependency in each package that uses them; `moodiary_di` only exports the runtime container.

## App theme and localization

- Keep `MaterialUiCompatibilityBridge` in `MaterialApp.builder`, outside `FlutterSmartDialog.init()`, so dialog overlays receive the compatibility theme.
- Use `material_ui`'s `GlobalMaterialLocalizations.delegates` from the mui barrel, together with `GlobalMuiLocalizations.delegate`; do not substitute the same-named delegates from `flutter_localizations`.
- Preserve both slang's `TranslationProvider` for app strings and Flutter's delegate chain for mui strings.

## Android channels and backend environments

- Run Android with an explicit `production` or `alpha` flavor. The APK task defaults to `production`; use `-- --flavor alpha --release` for an Alpha release build.
- The flavor controls app identity and distribution. `SELUMN_ENVIRONMENT` selects backend configuration independently; preserve both dimensions when changing bootstrap or build commands.
- Require the release signing key for `productionRelease`. Only `alphaRelease` may fall back to the debug key when that key is unavailable; debug/profile builds keep debug signing. See [android/SIGNING.md](android/SIGNING.md).
