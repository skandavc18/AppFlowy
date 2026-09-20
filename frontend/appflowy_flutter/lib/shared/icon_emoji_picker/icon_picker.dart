import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/string_extension.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_search_bar.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/util/debounce.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_icon_popup.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Icon;

import 'colors.dart';
import 'icon_color_picker.dart';

// cache the icon groups to avoid loading them multiple times
List<IconGroup>? kIconGroups;
const _kRecentIconGroupName = 'Recent';

/// Compiled catalogues are available on request; asset packs join when loaded.
Iterable<IconGroup> get allLoadedIconGroups sync* {
  yield* appFlowyDefaultIconGroups;
  yield* kIconPacks.expand(loadedIconGroupsOf);
}

// Resolve only the requested pack. Iterating every compiled catalogue here
// would initialize Vivid even when a cold sidebar only needs a line icon.
Icon? findLoadedIcon(String groupName, String iconName) =>
    loadedIconGroupsOf(iconPackForGroup(groupName))
        .firstWhereOrNull((group) => group.name == groupName)
        ?.icons
        .firstWhereOrNull((icon) => icon.name == iconName);

// A mixed Recent group is presentation only. Keep each item's persisted group
// attached even after filtering or a selection changes the stored recent order.
class _RecentPickerIcon extends Icon {
  _RecentPickerIcon(RecentIcon recent)
      : groupName = recent.groupName,
        super(
          name: recent.name,
          keywords: recent.keywords,
          content: recent.content,
        );

  final String groupName;

  @override
  bool get isColorful => iconPackForGroup(groupName).isColorful;
}

String _storedIconGroupName(IconGroup group, Icon icon) =>
    icon is _RecentPickerIcon ? icon.groupName : group.name;

extension IconGroupFilter on List<IconGroup> {
  String? findSvgContent(String key) {
    final values = key.split('/');
    if (values.length != 2) {
      return null;
    }
    return findLoadedIcon(values[0], values[1])?.content;
  }

  (IconGroup, Icon) randomIcon() {
    final random = Random();
    final group = this[random.nextInt(length)];
    final icon = group.icons[random.nextInt(group.icons.length)];
    return (group, icon);
  }
}

Future<List<IconGroup>> loadIconGroups() async {
  if (kIconGroups != null) {
    return kIconGroups!;
  }
  final groups = await loadIconPack(kDefaultIconPack);
  kIconGroups = groups;
  return groups;
}

class IconPickerResult {
  IconPickerResult(this.data, this.isRandom);

  final IconsData data;
  final bool isRandom;
}

extension IconsDataToIconPickerResultExtension on IconsData {
  IconPickerResult toResult({bool isRandom = false}) =>
      IconPickerResult(this, isRandom);
}

class FlowyIconPicker extends StatefulWidget {
  const FlowyIconPicker({
    super.key,
    required this.onSelectedIcon,
    required this.enableBackgroundColorSelection,
    this.iconPerLine = 9,
    this.ensureFocus = false,
    this.fixedPack,
  });

  final bool enableBackgroundColorSelection;
  final ValueChanged<IconPickerResult> onSelectedIcon;
  final int iconPerLine;
  final bool ensureFocus;

  /// A dedicated tab can reuse search, selection and colors without showing
  /// the library style switcher or allowing it to leave its own catalogue.
  final IconPack? fixedPack;

  @override
  State<FlowyIconPicker> createState() => _FlowyIconPickerState();
}

class _FlowyIconPickerState extends State<FlowyIconPicker> {
  final List<IconGroup> iconGroups = [];
  bool loaded = false;
  IconPack selectedPack = kDefaultIconPack;
  final ValueNotifier<String> keyword = ValueNotifier('');
  final debounce = Debounce(duration: const Duration(milliseconds: 150));

  Future<void> loadIcons() async {
    final pack = selectedPack;
    final packIcons = await loadIconPack(pack);
    if (!mounted || pack != selectedPack) {
      return;
    }

    final groups = <IconGroup>[];
    // recent icons are only meaningful next to the pack they belong to
    if (pack == kDefaultIconPack) {
      final recentIcons = await RecentIcons.getIcons();
      if (!mounted || pack != selectedPack) {
        return;
      }
      if (recentIcons.isNotEmpty) {
        final filterRecentIcons = recentIcons
            .sublist(
              0,
              min(recentIcons.length, widget.iconPerLine),
            )
            .skipWhile((e) => e.groupName.isEmpty)
            .map(_RecentPickerIcon.new)
            .toList();
        if (filterRecentIcons.isNotEmpty) {
          groups.add(
            IconGroup(
              name: _kRecentIconGroupName,
              icons: filterRecentIcons,
            ),
          );
        }
      }
    }
    groups.addAll(packIcons);

    setState(() {
      iconGroups
        ..clear()
        ..addAll(groups);
      loaded = true;
    });
  }

  void _selectPack(IconPack pack) {
    if (pack == selectedPack) {
      return;
    }
    setState(() {
      selectedPack = pack;
      loaded = isIconPackLoaded(pack);
      iconGroups.clear();
    });
    unawaited(loadIcons());
  }

  @override
  void initState() {
    super.initState();
    selectedPack = widget.fixedPack ?? kDefaultIconPack;
    if (isIconPackLoaded(selectedPack)) {
      iconGroups.addAll(loadedIconGroupsOf(selectedPack));
      loaded = true;
    }
    unawaited(loadIcons());
  }

  @override
  void didUpdateWidget(covariant FlowyIconPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fixedPack != widget.fixedPack) {
      _selectPack(widget.fixedPack ?? kDefaultIconPack);
    }
  }

  @override
  void dispose() {
    keyword.dispose();
    debounce.dispose();
    iconGroups.clear();
    loaded = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: IconSearchBar(
            ensureFocus: widget.ensureFocus,
            onRandomTap: () {
              final value = iconGroups.isEmpty ? null : iconGroups.randomIcon();
              if (value == null) {
                return;
              }
              final groupName = _storedIconGroupName(value.$1, value.$2);
              final color = widget.enableBackgroundColorSelection &&
                      !iconPackForGroup(groupName).isColorful
                  ? generateRandomSpaceColor()
                  : null;
              widget.onSelectedIcon(
                IconsData(
                  groupName,
                  value.$2.name,
                  color,
                ).toResult(isRandom: true),
              );
              RecentIcons.putIcon(RecentIcon(value.$2, groupName));
            },
            onKeywordChanged: (keyword) => {
              debounce.call(() {
                this.keyword.value = keyword;
              }),
            },
          ),
        ),
        if (widget.fixedPack == null) _buildStyleSelector(context),
        Expanded(
          child: loaded
              ? _buildIcons(iconGroups)
              : const Center(
                  child: SizedBox.square(
                    dimension: 24.0,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildStyleSelector(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 10.0),
      // Large text can wrap onto several lines in a narrow popup. Keep the
      // grid usable; later styles remain scrollable and keyboard reachable.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 144),
        child: SingleChildScrollView(
          key: const ValueKey('icon-picker-styles'),
          primary: false,
          child: Wrap(
            spacing: 6.0,
            runSpacing: 6.0,
            children: kIconPacks
                .map(
                  (pack) => _IconStyleChip(
                    key: ValueKey('icon-pack-${pack.id}'),
                    label: pack.displayName,
                    isSelected: pack == selectedPack,
                    onTap: () => _selectPack(pack),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildIcons(List<IconGroup> iconGroups) {
    return ValueListenableBuilder(
      valueListenable: keyword,
      builder: (_, keyword, __) {
        if (keyword.isNotEmpty) {
          final filteredIconGroups = iconGroups
              .map((iconGroup) => iconGroup.filter(keyword))
              .where((iconGroup) => iconGroup.icons.isNotEmpty)
              .toList();
          return IconPicker(
            iconGroups: filteredIconGroups,
            enableBackgroundColorSelection:
                widget.enableBackgroundColorSelection,
            onSelectedIcon: (r) => widget.onSelectedIcon.call(r.toResult()),
            iconPerLine: widget.iconPerLine,
            pack: selectedPack,
          );
        }
        return IconPicker(
          iconGroups: iconGroups,
          enableBackgroundColorSelection: widget.enableBackgroundColorSelection,
          onSelectedIcon: (r) => widget.onSelectedIcon.call(r.toResult()),
          iconPerLine: widget.iconPerLine,
          pack: selectedPack,
        );
      },
    );
  }
}

class _IconStyleChip extends StatelessWidget {
  const _IconStyleChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedColor = Theme.of(context).colorScheme.primary;
    return TextButton(
      onPressed: onTap,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size.zero),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        splashFactory: NoSplash.splashFactory,
        animationDuration: const Duration(milliseconds: 120),
        backgroundColor: WidgetStatePropertyAll(
          isSelected
              ? selectedColor.withValues(alpha: 0.12)
              : Colors.transparent,
        ),
        overlayColor: WidgetStatePropertyAll(_pickerHoverColor(context)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.focused)
                ? selectedColor
                : isSelected
                    ? selectedColor.withValues(alpha: 0.5)
                    : context.pickerButtonBoarderColor,
          ),
        ),
      ),
      child: Semantics(
        selected: isSelected,
        child: FlowyText(
          label,
          fontSize: 12,
          figmaLineHeight: 18.0,
          color: isSelected ? selectedColor : context.pickerTextColor,
        ),
      ),
    );
  }
}

Color _pickerHoverColor(BuildContext context) => PaperTheme.isEnabled(context)
    ? PaperTheme.hoverOverlay
    : Theme.of(context).colorScheme.primary.withValues(alpha: 0.08);

class IconsData {
  IconsData(this.groupName, this.iconName, this.color);

  final String groupName;
  final String iconName;
  final String? color;

  String get iconString => jsonEncode({
        'groupName': groupName,
        'iconName': iconName,
        if (color != null) 'color': color,
      });

  EmojiIconData toEmojiIconData() => EmojiIconData.icon(this);

  IconsData noColor() => IconsData(groupName, iconName, null);

  static IconsData fromJson(dynamic json) {
    return IconsData(
      json['groupName'],
      json['iconName'],
      json['color'],
    );
  }

  String? get svgString => findLoadedIcon(groupName, iconName)?.content;
}

class IconPicker extends StatefulWidget {
  const IconPicker({
    super.key,
    required this.onSelectedIcon,
    required this.enableBackgroundColorSelection,
    required this.iconGroups,
    required this.iconPerLine,
    this.pack = kDefaultIconPack,
  });

  final List<IconGroup> iconGroups;
  final int iconPerLine;
  final bool enableBackgroundColorSelection;
  final IconPack pack;
  final ValueChanged<IconsData> onSelectedIcon;

  @override
  State<IconPicker> createState() => _IconPickerState();
}

class _IconPickerState extends State<IconPicker> {
  final mutex = PopoverMutex();
  PopoverController? childPopoverController;

  @override
  void dispose() {
    super.dispose();
    childPopoverController = null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: hideColorSelector,
      child: NotificationListener(
        onNotification: (notificationInfo) {
          if (notificationInfo is ScrollStartNotification) {
            hideColorSelector();
          }
          return true;
        },
        child: ListView.builder(
          itemCount: widget.iconGroups.length,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          itemBuilder: (context, index) {
            final iconGroup = widget.iconGroups[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FlowyText(
                  iconGroup.displayName.capitalize(),
                  fontSize: 12,
                  figmaLineHeight: 18.0,
                  color: context.pickerTextColor,
                ),
                const VSpace(4.0),
                LayoutBuilder(
                  builder: (context, constraints) => GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: min(
                        widget.iconPerLine,
                        max(1, (constraints.maxWidth / 36).floor()),
                      ),
                    ),
                    itemCount: iconGroup.icons.length,
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    itemBuilder: (context, index) {
                      final icon = iconGroup.icons[index];
                      final groupName = _storedIconGroupName(iconGroup, icon);
                      // Recents deserialize without runtime metadata and can
                      // mix packs. Their persisted identity owns the palette.
                      final isColorful = iconPackForGroup(groupName).isColorful;
                      // a multi-color icon brings its own palette, so there is
                      // nothing to tint
                      return widget.enableBackgroundColorSelection &&
                              !isColorful
                          ? _Icon(
                              icon: icon,
                              mutex: mutex,
                              onOpen: (childPopoverController) {
                                this.childPopoverController =
                                    childPopoverController;
                              },
                              onSelectedColor: (context, color) {
                                widget.onSelectedIcon(
                                  IconsData(
                                    groupName,
                                    icon.name,
                                    color,
                                  ),
                                );
                                RecentIcons.putIcon(
                                    RecentIcon(icon, groupName),);
                                PopoverContainer.of(context).close();
                              },
                            )
                          : _IconNoBackground(
                              key: ValueKey(
                                  'picker-icon-$groupName/${icon.name}',),
                              icon: icon,
                              isColorful: isColorful,
                              onSelectedIcon: () {
                                widget.onSelectedIcon(
                                  IconsData(
                                    groupName,
                                    icon.name,
                                    null,
                                  ),
                                );
                                RecentIcons.putIcon(
                                    RecentIcon(icon, groupName),);
                              },
                            );
                    },
                  ),
                ),
                const VSpace(12.0),
                if (index == widget.iconGroups.length - 1) ...[
                  StreamlinePermit(pack: widget.pack),
                  const VSpace(12.0),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  void hideColorSelector() {
    childPopoverController?.close();
    childPopoverController = null;
  }
}

class _IconNoBackground extends StatelessWidget {
  const _IconNoBackground({
    super.key,
    required this.icon,
    required this.onSelectedIcon,
    this.isSelected = false,
    this.isColorful = false,
  });

  final Icon icon;
  final bool isSelected;
  final bool isColorful;
  final VoidCallback onSelectedIcon;

  @override
  Widget build(BuildContext context) {
    if (isColorful) {
      return Tooltip(
        message: icon.displayName,
        preferBelow: false,
        excludeFromSemantics: true,
        child: TextButton(
          onPressed: onSelectedIcon,
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size.zero),
            padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.standard,
            splashFactory: NoSplash.splashFactory,
            backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
            overlayColor: WidgetStatePropertyAll(_pickerHoverColor(context)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            side: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? BorderSide(color: Theme.of(context).colorScheme.primary)
                  : BorderSide.none,
            ),
          ),
          child: Semantics(
            label: icon.displayName,
            child: ExcludeSemantics(
              child: Center(
                // These are illustrations in fixed grid cells, not text.
                // FlowySvg otherwise scales its paint outside the cell at 2x.
                child: MediaQuery.withNoTextScaling(
                  child: FlowySvg.string(
                    icon.content,
                    size: const Size.square(24),
                    blendMode: null,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return FlowyTooltip(
      message: icon.displayName,
      preferBelow: false,
      child: FlowyButton(
        isSelected: isSelected,
        useIntrinsicWidth: true,
        onTap: () => onSelectedIcon(),
        margin: const EdgeInsets.all(8.0),
        text: Center(
          child: FlowySvg.string(
            icon.content,
            size: const Size.square(20),
            color: context.pickerIconColor,
            opacity: 0.7,
          ),
        ),
      ),
    );
  }
}

class _Icon extends StatefulWidget {
  const _Icon({
    required this.icon,
    required this.mutex,
    required this.onSelectedColor,
    this.onOpen,
  });

  final Icon icon;
  final PopoverMutex mutex;
  final void Function(BuildContext context, String color) onSelectedColor;
  final ValueChanged<PopoverController>? onOpen;

  @override
  State<_Icon> createState() => _IconState();
}

class _IconState extends State<_Icon> {
  final PopoverController _popoverController = PopoverController();
  bool isSelected = false;

  @override
  void dispose() {
    super.dispose();
    _popoverController.close();
  }

  @override
  Widget build(BuildContext context) {
    return AppFlowyPopover(
      direction: PopoverDirection.bottomWithCenterAligned,
      controller: _popoverController,
      offset: const Offset(0, 6),
      mutex: widget.mutex,
      onClose: () {
        updateIsSelected(false);
      },
      clickHandler: PopoverClickHandler.gestureDetector,
      child: _IconNoBackground(
        icon: widget.icon,
        isSelected: isSelected,
        onSelectedIcon: () {
          updateIsSelected(true);
          _popoverController.show();
          widget.onOpen?.call(_popoverController);
        },
      ),
      popupBuilder: (context) {
        return Container(
          padding: const EdgeInsets.all(6.0),
          child: IconColorPicker(
            onSelected: (color) => widget.onSelectedColor(context, color),
          ),
        );
      },
    );
  }

  void updateIsSelected(bool isSelected) {
    setState(() {
      this.isSelected = isSelected;
    });
  }
}

class StreamlinePermit extends StatelessWidget {
  const StreamlinePermit({
    super.key,
    this.pack = kDefaultIconPack,
  });

  final IconPack pack;

  @override
  Widget build(BuildContext context) {
    // Open source icons from <the library the current style comes from>
    // RichText does not inherit the theme's font the way Text does.
    final textStyle = DefaultTextStyle.of(context).style.copyWith(
          fontSize: 12.0,
          height: 18.0 / 12.0,
          fontWeight: FontWeight.w500,
          color: context.pickerTextColor,
        );
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '${LocaleKeys.emoji_openSourceIconsFrom.tr()} ',
            style: textStyle,
          ),
          TextSpan(
            text: pack.attribution,
            style: textStyle.copyWith(
              decoration: TextDecoration.underline,
              color: Theme.of(context).colorScheme.primary,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                afLaunchUrlString(pack.attributionUrl);
              },
          ),
        ],
      ),
    );
  }
}
