import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_embed/youtube_video_download.dart';
import 'package:appflowy/shared/patterns/common_patterns.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/style_widget/button.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flowy_infra_ui/style_widget/text_field.dart';
import 'package:flowy_infra_ui/widget/spacing.dart';
import 'package:flutter/material.dart';
import 'package:universal_platform/universal_platform.dart';

class FileUploadMenu extends StatefulWidget {
  const FileUploadMenu({
    super.key,
    required this.onInsertLocalFile,
    this.onInsertLocalFileWithOptions,
    this.onInsertNetworkFile,
    this.onInsertNetworkFileWithOptions,
    this.onInsertNetworkFileWithPreviewOptions,
    this.allowMultipleFiles = false,
    this.defaultShowPreview = false,
  }) : assert(
          onInsertNetworkFile != null || onInsertNetworkFileWithOptions != null,
        );

  final void Function(List<XFile> files) onInsertLocalFile;
  final void Function(List<XFile> files, bool showPreview)?
      onInsertLocalFileWithOptions;
  final void Function(String url)? onInsertNetworkFile;
  final Future<void> Function(String url, bool saveOffline)?
      onInsertNetworkFileWithOptions;
  final Future<void> Function(
    String url,
    bool saveOffline,
    bool showPreview,
  )? onInsertNetworkFileWithPreviewOptions;
  final bool allowMultipleFiles;
  final bool defaultShowPreview;

  @override
  State<FileUploadMenu> createState() => _FileUploadMenuState();
}

class _FileUploadMenuState extends State<FileUploadMenu> {
  int currentTab = 0;
  late bool showPreview = widget.defaultShowPreview;

  @override
  Widget build(BuildContext context) {
    // ClipRRect is used to clip the tab indicator, so the animation doesn't overflow the dialog
    return ClipRRect(
      child: DefaultTabController(
        length: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              onTap: (value) => setState(() => currentTab = value),
              isScrollable: true,
              indicatorWeight: 3,
              tabAlignment: TabAlignment.start,
              indicatorSize: TabBarIndicatorSize.label,
              labelPadding: EdgeInsets.zero,
              padding: EdgeInsets.zero,
              overlayColor: WidgetStatePropertyAll(
                UniversalPlatform.isDesktop
                    ? Theme.of(context).colorScheme.secondary
                    : Colors.transparent,
              ),
              tabs: [
                _Tab(
                  title: LocaleKeys.document_plugins_file_uploadTab.tr(),
                  isSelected: currentTab == 0,
                ),
                _Tab(
                  title: LocaleKeys.document_plugins_file_networkTab.tr(),
                  isSelected: currentTab == 1,
                ),
              ],
            ),
            const Divider(height: 0),
            if (currentTab == 0) ...[
              _FileUploadLocal(
                allowMultipleFiles: widget.allowMultipleFiles,
                onFilesPicked: (files) {
                  if (files.isNotEmpty) {
                    final callback = widget.onInsertLocalFileWithOptions;
                    callback != null
                        ? callback(files, showPreview)
                        : widget.onInsertLocalFile(files);
                  }
                },
              ),
            ] else ...[
              _FileUploadNetwork(
                onSubmit: (url, saveOffline) async {
                  final previewCallback =
                      widget.onInsertNetworkFileWithPreviewOptions;
                  if (previewCallback != null) {
                    await previewCallback(url, saveOffline, showPreview);
                    return;
                  }
                  final callback = widget.onInsertNetworkFileWithOptions;
                  if (callback != null) {
                    await callback(url, saveOffline);
                  } else {
                    widget.onInsertNetworkFile!(url);
                  }
                },
              ),
            ],
            CheckboxListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: const FlowyText('Show preview when supported'),
              value: showPreview,
              onChanged: (value) =>
                  setState(() => showPreview = value ?? false),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.title, this.isSelected = false});

  final String title;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 12.0,
        right: 12.0,
        bottom: 8.0,
        top: UniversalPlatform.isMobile ? 0 : 8.0,
      ),
      child: FlowyText.semibold(
        title,
        color: isSelected
            ? AFThemeExtension.of(context).strongText
            : Theme.of(context).hintColor,
      ),
    );
  }
}

class _FileUploadLocal extends StatefulWidget {
  const _FileUploadLocal({
    required this.onFilesPicked,
    this.allowMultipleFiles = false,
  });

  final void Function(List<XFile>) onFilesPicked;
  final bool allowMultipleFiles;

  @override
  State<_FileUploadLocal> createState() => _FileUploadLocalState();
}

class _FileUploadLocalState extends State<_FileUploadLocal> {
  bool isDragging = false;

  @override
  Widget build(BuildContext context) {
    final constraints =
        UniversalPlatform.isMobile ? const BoxConstraints(minHeight: 92) : null;

    if (UniversalPlatform.isMobile) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 32,
          child: FlowyButton(
            backgroundColor: Theme.of(context).colorScheme.primary,
            hoverColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
            showDefaultBoxDecorationOnMobile: true,
            margin: const EdgeInsets.all(5),
            text: FlowyText(
              LocaleKeys.document_plugins_file_uploadMobile.tr(),
              textAlign: TextAlign.center,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            onTap: () => _uploadFile(context),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: DropTarget(
        onDragEntered: (_) => setState(() => isDragging = true),
        onDragExited: (_) => setState(() => isDragging = false),
        onDragDone: (details) => widget.onFilesPicked(details.files),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _uploadFile(context),
            child: FlowyHover(
              resetHoverOnRebuild: false,
              isSelected: () => isDragging,
              style: HoverStyle(
                borderRadius: BorderRadius.circular(10),
                hoverColor:
                    isDragging ? AFThemeExtension.of(context).tint9 : null,
              ),
              child: Container(
                height: 172,
                constraints: constraints,
                child: DottedBorder(
                  dashPattern: const [3, 3],
                  radius: const Radius.circular(8),
                  borderType: BorderType.RRect,
                  color: isDragging
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).hintColor,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isDragging) ...[
                          FlowyText(
                            LocaleKeys.document_plugins_file_dropFileToUpload
                                .tr(),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).hintColor,
                          ),
                        ] else ...[
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: LocaleKeys
                                      .document_plugins_file_fileUploadHint
                                      .tr(),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context).hintColor,
                                  ),
                                ),
                                TextSpan(
                                  text: LocaleKeys
                                      .document_plugins_file_fileUploadHintSuffix
                                      .tr(),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _uploadFile(BuildContext context) async {
    final result = await getIt<FilePickerService>().pickFiles(
      dialogTitle: '',
      allowMultiple: widget.allowMultipleFiles,
    );

    final List<XFile> files = result?.files.isNotEmpty ?? false
        ? result!.files.map((f) => f.xFile).toList()
        : const [];

    widget.onFilesPicked(files);
  }
}

class _FileUploadNetwork extends StatefulWidget {
  const _FileUploadNetwork({required this.onSubmit});

  final Future<void> Function(String url, bool saveOffline) onSubmit;

  @override
  State<_FileUploadNetwork> createState() => _FileUploadNetworkState();
}

class _FileUploadNetworkState extends State<_FileUploadNetwork> {
  bool isUrlValid = true;
  bool saveOffline = false;
  bool isSubmitting = false;
  String inputText = '';

  @override
  Widget build(BuildContext context) {
    final constraints =
        UniversalPlatform.isMobile ? const BoxConstraints(minHeight: 92) : null;

    return Container(
      padding: const EdgeInsets.all(16),
      constraints: constraints,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlowyTextField(
            hintText: LocaleKeys.document_plugins_file_networkHint.tr(),
            onChanged: (value) {
              setState(() {
                inputText = value;
                if (!isYoutubeVideoUrl(value)) {
                  saveOffline = false;
                }
              });
            },
            onEditingComplete: submit,
          ),
          if (!isUrlValid) ...[
            const VSpace(4),
            FlowyText(
              LocaleKeys.document_plugins_file_networkUrlInvalid.tr(),
              color: Theme.of(context).colorScheme.error,
              maxLines: 3,
              textAlign: TextAlign.start,
            ),
          ],
          if (isYoutubeVideoUrl(inputText)) ...[
            const VSpace(8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: FlowyText(
                LocaleKeys.document_plugins_file_saveForOfflineViewing.tr(),
              ),
              value: saveOffline,
              onChanged: isSubmitting
                  ? null
                  : (value) => setState(() => saveOffline = value ?? false),
            ),
          ],
          const VSpace(16),
          SizedBox(
            height: 32,
            child: FlowyButton(
              backgroundColor: Theme.of(context).colorScheme.primary,
              hoverColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
              showDefaultBoxDecorationOnMobile: true,
              margin: const EdgeInsets.all(5),
              text: FlowyText(
                LocaleKeys.document_plugins_file_networkAction.tr(),
                textAlign: TextAlign.center,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
              onTap: isSubmitting ? null : submit,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> submit() async {
    if (checkUrlValidity(inputText)) {
      setState(() => isSubmitting = true);
      try {
        await widget.onSubmit(inputText, saveOffline);
      } finally {
        if (mounted) {
          setState(() => isSubmitting = false);
        }
      }
      return;
    }

    setState(() => isUrlValid = false);
  }

  bool checkUrlValidity(String url) => hrefRegex.hasMatch(url);
}
