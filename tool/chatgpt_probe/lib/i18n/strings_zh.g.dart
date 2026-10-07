///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import

part of 'strings.g.dart';

// Path: <root>
typedef ProbeTranslationsZh = ProbeTranslations; // ignore: unused_element

class ProbeTranslations with BaseTranslations<ProbeLocale, ProbeTranslations> {
  /// Returns the current translations of the given [context].
  ///
  /// Usage:
  /// final probeL10n = ProbeTranslations.of(context);
  static ProbeTranslations of(BuildContext context) =>
      InheritedLocaleData.of<ProbeLocale, ProbeTranslations>(context)
          .translations;

  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [ProbeLocale.build] is preferred.
  ProbeTranslations({
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
             locale: ProbeLocale.zh,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           );

  /// Metadata for the translations of <zh>.
  final TranslationMetadata<ProbeLocale, ProbeTranslations> _meta;
  @override
  TranslationMetadata<ProbeLocale, ProbeTranslations> get $meta => _meta;

  late final ProbeTranslations _root = this; // ignore: unused_field

  ProbeTranslations $copyWith({
    TranslationMetadata<ProbeLocale, ProbeTranslations>? meta,
  }) => ProbeTranslations(meta: meta ?? this.$meta);

  // Translations

  /// zh: 'Selume 订阅验证'
  String get title => 'Selume 订阅验证';

  /// zh: 'ANDROID · 连接测试'
  String get badge => 'ANDROID · 连接测试';

  /// zh: '让日记连接你的 ChatGPT'
  String get heading => '让日记连接你的 ChatGPT';

  /// zh: '在这台手机上验证登录、订阅授权和一次完整回复。此独立测试应用不会访问你的日记。'
  String get intro => '在这台手机上验证登录、订阅授权和一次完整回复。此独立测试应用不会访问你的日记。';

  /// zh: '1. 连接账号'
  String get accountTitle => '1. 连接账号';

  /// zh: 'Continue with ChatGPT'
  String get login => 'Continue with ChatGPT';

  /// zh: '在官方页面登录并授权，最多等待 15 分钟。浏览器显示完成后，请手动回到此应用。'
  String get loginHint => '在官方页面登录并授权，最多等待 15 分钟。浏览器显示完成后，请手动回到此应用。';

  /// zh: '已收到登录回调。请手动返回 Selume 订阅验证，查看验证结果。'
  String get callbackMessage => '已收到登录回调。请手动返回 Selume 订阅验证，查看验证结果。';

  /// zh: '粘贴授权结果'
  String get pasteCallback => '粘贴授权结果';

  /// zh: '如果浏览器已跳到 127.0.0.1，但页面打不开，请复制地址栏的完整地址，回到这里粘贴。请在本次登录开始后的 15 分钟内完成。'
  String get pasteCallbackHint =>
      '如果浏览器已跳到 127.0.0.1，但页面打不开，请复制地址栏的完整地址，回到这里粘贴。请在本次登录开始后的 15 分钟内完成。';

  /// zh: '只粘贴本次登录返回的完整 http://127.0.0.1:端口/auth/callback?... 地址。链接包含一次性授权信息，仅在此应用内处理，请勿发给他人。'
  String get pasteCallbackInstructions =>
      '只粘贴本次登录返回的完整 http://127.0.0.1:端口/auth/callback?... 地址。链接包含一次性授权信息，仅在此应用内处理，请勿发给他人。';

  /// zh: '浏览器返回地址'
  String get callbackUrlLabel => '浏览器返回地址';

  /// zh: '继续验证'
  String get callbackSubmit => '继续验证';

  /// zh: '正在处理授权结果'
  String get callbackSubmitting => '正在处理授权结果';

  /// zh: '关闭'
  String get callbackClose => '关闭';

  /// zh: '地址不完整或与本次登录不匹配。请复制当前浏览器返回的完整地址，不要使用 OpenAI 登录页或旧的授权地址。'
  String get callbackInputError =>
      '地址不完整或与本次登录不匹配。请复制当前浏览器返回的完整地址，不要使用 OpenAI 登录页或旧的授权地址。';

  /// zh: '本次授权已结束或过期，请关闭此窗口并重新登录。'
  String get callbackExpiredError => '本次授权已结束或过期，请关闭此窗口并重新登录。';

  /// zh: '取消登录'
  String get cancel => '取消登录';

  /// zh: '已连接账号'
  String get account => '已连接账号';

  /// zh: '已获得 ChatGPT 计划使用权限'
  String get permissionOn => '已获得 ChatGPT 计划使用权限';

  /// zh: '尚未获得订阅使用权限，请重新授权。'
  String get permissionOff => '尚未获得订阅使用权限，请重新授权。';

  /// zh: '重新授权'
  String get reauthorize => '重新授权';

  /// zh: '退出并清除凭据'
  String get signOut => '退出并清除凭据';

  /// zh: '2. 发送测试消息'
  String get modelTitle => '2. 发送测试消息';

  /// zh: '选择此账号可用的模型。每次测试会使用你的 ChatGPT 计划或可用积分。'
  String get modelHint => '选择此账号可用的模型。每次测试会使用你的 ChatGPT 计划或可用积分。';

  /// zh: '模型'
  String get modelLabel => '模型';

  /// zh: '请选择模型'
  String get chooseModel => '请选择模型';

  /// zh: '获取可用模型'
  String get loadModels => '获取可用模型';

  /// zh: '发送测试消息'
  String get test => '发送测试消息';

  /// zh: '正在测试，请等待完整回复…'
  String get testRunning => '正在测试，请等待完整回复…';

  /// zh: '测试成功'
  String get testSuccess => '测试成功';

  /// zh: '测试失败，未确认完整回复'
  String get testFailed => '测试失败，未确认完整回复';

  /// zh: '已收到的部分回复（尚未验证完成）'
  String get partialReply => '已收到的部分回复（尚未验证完成）';

  /// zh: '测试内容：请只回复 OK。'
  String get testPrompt => '测试内容：请只回复 OK。';

  /// zh: '刷新登录凭据并测试'
  String get refreshTest => '刷新登录凭据并测试';

  /// zh: '刷新测试会更新登录凭据并再发送一条消息；用于确认凭据续期可用。'
  String get refreshHint => '刷新测试会更新登录凭据并再发送一条消息；用于确认凭据续期可用。';

  /// zh: '验证进度'
  String get resultTitle => '验证进度';

  /// zh: '测试回复'
  String get replyTitle => '测试回复';

  /// zh: '等待测试。只有服务端确认回复完成，才会标记为通过。'
  String get replyPending => '等待测试。只有服务端确认回复完成，才会标记为通过。';

  /// zh: '查看 ChatGPT 用量'
  String get usage => '查看 ChatGPT 用量';

  /// zh: '在 ChatGPT 的用量设置中核对本应用的授权与限额。一次短回复可能不会明显改变用量百分比。'
  String get usageHint => '在 ChatGPT 的用量设置中核对本应用的授权与限额。一次短回复可能不会明显改变用量百分比。';

  /// zh: '完整回复成功后，关闭并重新打开此应用，再发送一次测试消息，检查登录状态恢复。'
  String get restartHint => '完整回复成功后，关闭并重新打开此应用，再发送一次测试消息，检查登录状态恢复。';

  /// zh: '本次验证未完成'
  String get errorTitle => '本次验证未完成';

  /// zh: '失败步骤'
  String get failedAt => '失败步骤';

  /// zh: '诊断代码'
  String get diagnostic => '诊断代码';

  /// zh: '复制诊断信息'
  String get copy => '复制诊断信息';

  /// zh: '已复制不含凭据的诊断信息'
  String get copied => '已复制不含凭据的诊断信息';

  /// zh: '请根据诊断代码检查当前步骤，然后重试。'
  String get genericError => '请根据诊断代码检查当前步骤，然后重试。';

  /// zh: '接口返回了网页，未收到模型回复流。可能是网络中间环节或服务端返回的页面。请复制诊断信息，保留当前能联网的代理设置。'
  String get htmlResponseError =>
      '接口返回了网页，未收到模型回复流。可能是网络中间环节或服务端返回的页面。请复制诊断信息，保留当前能联网的代理设置。';

  /// zh: '接口返回了 JSON 数据，未收到预期的回复流。此次测试未通过，请复制诊断信息以便继续定位。'
  String get jsonResponseError =>
      '接口返回了 JSON 数据，未收到预期的回复流。此次测试未通过，请复制诊断信息以便继续定位。';

  /// zh: '响应类型不符合预期，无法确认模型是否完成回复。请复制诊断信息以便继续定位。'
  String get responseFormatError => '响应类型不符合预期，无法确认模型是否完成回复。请复制诊断信息以便继续定位。';

  /// zh: '接口返回了 HTTP 200，但正文为空，没有收到模型回复。请复制诊断信息，保留当前能联网的代理设置。'
  String get emptyResponseError =>
      '接口返回了 HTTP 200，但正文为空，没有收到模型回复。请复制诊断信息，保留当前能联网的代理设置。';

  /// zh: '未收到有效的完整回复。即使已出现部分文字，也不能确认此次测试成功。请复制诊断信息。'
  String get incompleteResponseError =>
      '未收到有效的完整回复。即使已出现部分文字，也不能确认此次测试成功。请复制诊断信息。';

  /// zh: '无法连接服务，请检查手机网络后重试。临时网络错误不会清除登录信息。'
  String get networkError => '无法连接服务，请检查手机网络后重试。临时网络错误不会清除登录信息。';

  /// zh: '账号尚未授权使用 ChatGPT 计划，或该账号／工作空间暂不支持此功能。'
  String get permissionError => '账号尚未授权使用 ChatGPT 计划，或该账号／工作空间暂不支持此功能。';

  /// zh: '已达到计划或本应用的使用限额，请打开 ChatGPT 用量设置查看。'
  String get limitError => '已达到计划或本应用的使用限额，请打开 ChatGPT 用量设置查看。';

  /// zh: '登录验证未通过，请重新登录。'
  String get loginError => '登录验证未通过，请重新登录。';

  /// zh: '等待超时，请重新开始当前步骤。'
  String get timeoutError => '等待超时，请重新开始当前步骤。';

  /// zh: '未能在等待时间内收到浏览器授权结果，本次登录已结束。请关闭旧的浏览器授权页面，重新点击 Continue with ChatGPT；刷新旧的 127.0.0.1 页面无法继续。'
  String get authorizationTimeoutError =>
      '未能在等待时间内收到浏览器授权结果，本次登录已结束。请关闭旧的浏览器授权页面，重新点击 Continue with ChatGPT；刷新旧的 127.0.0.1 页面无法继续。';

  /// zh: '打开浏览器超时。请确认手机有可用浏览器，再重新点击 Continue with ChatGPT。'
  String get browserLaunchTimeoutError =>
      '打开浏览器超时。请确认手机有可用浏览器，再重新点击 Continue with ChatGPT。';

  /// zh: '本机凭据已清除，但未确认服务端撤销。你可以在 ChatGPT 设置中断开本应用。'
  String get revocationError => '本机凭据已清除，但未确认服务端撤销。你可以在 ChatGPT 设置中断开本应用。';

  Map<String, String> get phases => {
    'idle': '准备开始',
    'initializing': '正在读取安全存储',
    'restored': '已恢复保存的登录状态',
    'registering': '正在准备登录',
    'waiting_browser': '等待浏览器授权，请完成后返回应用',
    'pending_authorization': '已恢复未完成的登录，可粘贴浏览器授权结果继续',
    'exchanging': '正在交换授权凭据',
    'validating': '正在验证账号身份与订阅权限',
    'signed_in': '登录完成',
    'loading_models': '正在获取账号可用模型',
    'testing': '正在等待完整回复',
    'refreshing': '正在刷新登录凭据',
    'completed': '本次请求已完整完成',
    'signing_out': '正在退出账号',
    'signed_out': '已退出账号',
    'cancelled': '登录已取消',
    'failed': '验证未完成',
  };
  Map<String, String> get steps => {
    'callback': '手机收到授权回调',
    'identity': '账号身份校验通过',
    'permission': '已授予订阅使用权限',
    'models': '已获取账号可用模型',
    'response': '服务端确认回复完成',
    'refresh': '登录凭据刷新成功',
    'restored': '安全存储中的登录状态已恢复',
  };
}
