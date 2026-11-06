import 'package:url_launcher/url_launcher.dart';

/// 发布页地址。应用本身不联网，点一下交给系统浏览器打开。
const String kReleasePage =
    'https://github.com/ztff/recipe_book/releases/latest';

/// 用系统浏览器打开更新页面。
///
/// 应用自己不发任何网络请求，也就没有请求超时、被墙、限流这些事；
/// 打不开就提示一下，用户自己复制地址也行。
Future<bool> openReleasePage() async {
  try {
    return await launchUrl(
      Uri.parse(kReleasePage),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}
