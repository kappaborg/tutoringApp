import 'package:flutter/material.dart';

/// Hand-rolled localizations. ARB files in `l10n/` are the source of truth for
/// future codegen migration; right now we ship only English strings via this
/// class to avoid a build_runner step.
class AppStrings {
  AppStrings(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[Locale('en'), Locale('zh')];

  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings) ?? AppStrings(const Locale('en'));

  static const LocalizationsDelegate<AppStrings> delegate = _AppStringsDelegate();

  String get appTitle => _pick('Picture Book', '图画书');
  String get reader => _pick('Reader', '阅读');
  String get admin => _pick('Admin', '管理');
  String get settings => _pick('Settings', '设置');
  String get next => _pick('Next', '下一页');
  String get previous => _pick('Previous', '上一页');
  String pageOf(int current, int total) =>
      _pick('Page $current of $total', '第 $current 页 / 共 $total 页');
  String get noBooks =>
      _pick('No books yet. Add one in Admin to get started.', '还没有书。请到管理页面添加。');
  String get addBook => _pick('Add Book', '添加书本');
  String get chineseMeaning => _pick('Chinese', '中文');
  String get englishDefinition => _pick('English', '英文');
  String get speakWord => _pick('Speak word', '朗读单词');
  String get edit => _pick('Edit', '编辑');
  String get delete => _pick('Delete', '删除');
  String get save => _pick('Save', '保存');
  String get cancel => _pick('Cancel', '取消');
  String get noMeaningRecorded =>
      _pick('No meaning recorded for this word.', '尚未记录此单词的释义。');
  String get addMeaning => _pick('Add meaning', '添加释义');
  String get enterPin => _pick('Enter Teacher PIN', '输入教师密码');
  String get setPin => _pick('Set Teacher PIN', '设置教师密码');
  String get pinMismatch => _pick('Incorrect PIN.', '密码错误。');
  String get imageMissing =>
      _pick('Image missing — open in Admin to re-attach.', '图片丢失 — 请到管理页面重新上传。');
  String get backup => _pick('Backup', '备份');
  String get restore => _pick('Restore', '恢复');
  String get exportBackup => _pick('Export backup', '导出备份');
  String get importBackup => _pick('Import backup', '导入备份');
  String get verifiedOffline => _pick('No network — verified offline', '完全离线运行');

  // Activation
  String get activateTitle => _pick('Activate Picture Book', '激活图画书');
  String get activateSubtitle => _pick(
        'Paste the activation code you received after purchase.',
        '请粘贴购买后收到的激活码。',
      );
  String get activationCodeLabel => _pick('Activation code', '激活码');
  String get activate => _pick('Activate', '激活');
  String get activationFailed => _pick(
        'This code is not valid. Check that you copied the entire string.',
        '激活码无效，请确认已完整复制。',
      );
  String activationSuccess(String customer) =>
      _pick('Welcome, $customer!', '欢迎，$customer！');
  String licensedTo(String customer) =>
      _pick('Licensed to: $customer', '授权给：$customer');

  String _pick(String en, String zh) => locale.languageCode == 'zh' ? zh : en;
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppStrings.supportedLocales.any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppStrings> load(Locale locale) async => AppStrings(locale);

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}
