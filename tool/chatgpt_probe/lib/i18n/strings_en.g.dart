///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';

import 'strings.g.dart';

// Path: <root>
class ProbeTranslationsEn extends ProbeTranslations
    with BaseTranslations<ProbeLocale, ProbeTranslations> {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [ProbeLocale.build] is preferred.
  ProbeTranslationsEn({
    Map<String, Node>? overrides,
    PluralResolver? cardinalResolver,
    PluralResolver? ordinalResolver,
    TranslationMetadata<ProbeLocale, ProbeTranslations>? meta,
  }) : assert(
         overrides == null,
         'Set "translation_overrides: true" in order to enable this feature.',
       ),
       _meta =
           meta ??
           TranslationMetadata(
             locale: ProbeLocale.en,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           ),
       super(
         cardinalResolver: cardinalResolver,
         ordinalResolver: ordinalResolver,
       );

  /// Metadata for the translations of <en>.
  final TranslationMetadata<ProbeLocale, ProbeTranslations> _meta;
  @override
  TranslationMetadata<ProbeLocale, ProbeTranslations> get $meta => _meta;

  late final ProbeTranslationsEn _root = this; // ignore: unused_field

  @override
  ProbeTranslationsEn $copyWith({
    TranslationMetadata<ProbeLocale, ProbeTranslations>? meta,
  }) => ProbeTranslationsEn(meta: meta ?? this.$meta);

  // Translations
  @override
  String get title => 'Selume Plan Probe';
  @override
  String get badge => 'ANDROID · CONNECTION TEST';
  @override
  String get heading => 'Connect your diary to ChatGPT';
  @override
  String get intro =>
      'Verify sign-in, plan permission and one complete response on this phone. This separate test app does not access your diary.';
  @override
  String get accountTitle => '1. Connect your account';
  @override
  String get login => 'Continue with ChatGPT';
  @override
  String get loginHint =>
      'Sign in and authorize on the official page within 15 minutes. When the browser finishes, return to this app manually.';
  @override
  String get callbackMessage =>
      'Authorization callback received. Return to Selume Plan Probe to see the verification result.';
  @override
  String get pasteCallback => 'Paste authorization result';
  @override
  String get pasteCallbackHint =>
      'If the browser reaches 127.0.0.1 but cannot open the page, copy the complete address and paste it here. Complete this within 15 minutes of starting this sign-in.';
  @override
  String get pasteCallbackInstructions =>
      'Paste only the complete http://127.0.0.1:port/auth/callback?... address returned for this sign-in. It contains one-time authorization information. Handle it only in this app and do not send it to anyone.';
  @override
  String get callbackUrlLabel => 'Browser return address';
  @override
  String get callbackSubmit => 'Continue verification';
  @override
  String get callbackSubmitting => 'Processing authorization result';
  @override
  String get callbackClose => 'Close';
  @override
  String get callbackInputError =>
      'The address is incomplete or does not match this sign-in. Copy the complete browser return address, not the OpenAI sign-in page or an old authorization address.';
  @override
  String get callbackExpiredError =>
      'This sign-in has ended or expired. Close this dialog and start a new sign-in.';
  @override
  String get cancel => 'Cancel sign-in';
  @override
  String get account => 'Connected account';
  @override
  String get permissionOn => 'ChatGPT plan permission granted';
  @override
  String get permissionOff =>
      'Plan permission was not granted. Authorize again to continue.';
  @override
  String get reauthorize => 'Authorize again';
  @override
  String get signOut => 'Sign out and clear credentials';
  @override
  String get modelTitle => '2. Send a test message';
  @override
  String get modelHint =>
      'Choose an available model. Each test uses your ChatGPT plan or available credits.';
  @override
  String get modelLabel => 'Model';
  @override
  String get chooseModel => 'Choose a model';
  @override
  String get loadModels => 'Load available models';
  @override
  String get test => 'Send test message';
  @override
  String get testRunning => 'Testing. Waiting for a complete response…';
  @override
  String get testSuccess => 'Test succeeded';
  @override
  String get testFailed => 'Test failed. A complete response was not confirmed';
  @override
  String get partialReply => 'Partial response (completion not verified)';
  @override
  String get testPrompt => 'Test prompt: Reply with exactly OK.';
  @override
  String get refreshTest => 'Refresh credentials and test';
  @override
  String get refreshHint =>
      'This refreshes your credentials and sends another message to verify session renewal.';
  @override
  String get resultTitle => 'Verification progress';
  @override
  String get replyTitle => 'Test response';
  @override
  String get replyPending =>
      'Waiting for a test. A response passes only after the server confirms completion.';
  @override
  String get usage => 'View ChatGPT usage';
  @override
  String get usageHint =>
      'Check this app\'s permission and limits in ChatGPT usage settings. One short reply may not visibly change the usage percentage.';
  @override
  String get restartHint =>
      'After a completed response, close and reopen this app and send another test message to check session restoration.';
  @override
  String get errorTitle => 'Verification did not complete';
  @override
  String get failedAt => 'Failed step';
  @override
  String get diagnostic => 'Diagnostic code';
  @override
  String get copy => 'Copy diagnostics';
  @override
  String get copied => 'Copied diagnostics without credentials';
  @override
  String get genericError =>
      'Check the diagnostic code and retry the current step.';
  @override
  String get htmlResponseError =>
      'The endpoint returned a web page instead of a model response stream. This may come from the service or a network intermediary. Copy diagnostics and keep the proxy settings that provide connectivity.';
  @override
  String get jsonResponseError =>
      'The endpoint returned JSON instead of the expected response stream. The test did not pass. Copy diagnostics for further investigation.';
  @override
  String get responseFormatError =>
      'The response type was unexpected, so model completion could not be verified. Copy diagnostics for further investigation.';
  @override
  String get emptyResponseError =>
      'The endpoint returned HTTP 200 with an empty body. No model response was received. Copy diagnostics and keep the proxy settings that provide connectivity.';
  @override
  String get incompleteResponseError =>
      'A valid complete response was not received. Partial text does not confirm success. Copy diagnostics for further investigation.';
  @override
  String get networkError =>
      'Could not connect. Check your network and retry. Temporary network failures do not remove saved credentials.';
  @override
  String get permissionError =>
      'ChatGPT plan usage is not authorized or is unavailable for this account or workspace.';
  @override
  String get limitError =>
      'A plan or app usage limit was reached. Review ChatGPT usage settings.';
  @override
  String get loginError => 'Sign-in validation failed. Please sign in again.';
  @override
  String get timeoutError =>
      'The operation timed out. Please start this step again.';
  @override
  String get authorizationTimeoutError =>
      'The browser authorization result did not arrive before the deadline, so this sign-in has ended. Close the old authorization page and select Continue with ChatGPT again. Refreshing the old 127.0.0.1 page cannot resume it.';
  @override
  String get browserLaunchTimeoutError =>
      'Opening the browser timed out. Check that a browser is available on this phone, then select Continue with ChatGPT again.';
  @override
  String get revocationError =>
      'Local credentials were cleared, but remote revocation was not confirmed. Disconnect this app in ChatGPT settings.';
  @override
  Map<String, String> get phases => {
    'idle': 'Ready to begin',
    'initializing': 'Reading secure storage',
    'restored': 'Saved sign-in restored',
    'registering': 'Preparing sign-in',
    'waiting_browser':
        'Complete authorization in the browser, then return here',
    'pending_authorization':
        'Unfinished sign-in restored. Paste the browser result to continue',
    'exchanging': 'Exchanging authorization credentials',
    'validating': 'Verifying identity and plan permission',
    'signed_in': 'Signed in',
    'loading_models': 'Loading available models',
    'testing': 'Waiting for a complete response',
    'refreshing': 'Refreshing credentials',
    'completed': 'Request completed successfully',
    'signing_out': 'Signing out',
    'signed_out': 'Signed out',
    'cancelled': 'Sign-in cancelled',
    'failed': 'Verification did not complete',
  };
  @override
  Map<String, String> get steps => {
    'callback': 'Phone received the authorization callback',
    'identity': 'Account identity verified',
    'permission': 'ChatGPT plan permission granted',
    'models': 'Account model catalog loaded',
    'response': 'Server confirmed response completion',
    'refresh': 'Credentials refreshed successfully',
    'restored': 'Saved sign-in restored from secure storage',
  };
}
