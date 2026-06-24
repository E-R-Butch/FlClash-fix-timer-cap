import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' hide context;

class ResourcesView extends StatelessWidget {
  const ResourcesView({super.key});

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: context.appLocalizations.resources,
      body: ListView(
        children: [
          generateSectionV3(
            title: '配置',
            items: [
              const _GeoDataListItem(GeoResource.GEOIP),
              const _GeoDataListItem(GeoResource.GEOSITE),
              const _GeoDataListItem(GeoResource.MMDB),
              const _GeoDataListItem(GeoResource.ASN),
            ],
          ),
        ],
      ),
    );
  }
}

class _GeoDataListItem extends StatefulWidget {
  final GeoResource type;

  const _GeoDataListItem(this.type);

  @override
  State<_GeoDataListItem> createState() => _GeoDataListItemState();
}

class _GeoDataListItemState extends State<_GeoDataListItem> {
  final isUpdating = ValueNotifier<bool>(false);

  String get label => widget.type.name;

  String get fileName {
    return switch (widget.type) {
      GeoResource.MMDB => MMDB,
      GeoResource.ASN => ASN,
      GeoResource.GEOIP => GEOIP,
      GeoResource.GEOSITE => GEOSITE,
    };
  }

  Future<void> _updateUrl(String url, WidgetRef ref) async {
    final newUrl = await globalState.showCommonDialog<String>(
      child: UpdateGeoUrlFormDialog(
        title: label,
        url: url,
        defaultValue: defaultGeoXUrl[widget.type],
      ),
    );
    if (newUrl != null && newUrl != url && mounted) {
      try {
        if (!newUrl.isUrl) {
          throw 'Invalid url';
        }
        ref.read(patchClashConfigProvider.notifier).update((state) {
          return state.copyWith(
            geoXUrl: {...state.geoXUrl, widget.type: newUrl},
          );
        });
      } catch (e) {
        globalState.showMessage(
          title: label,
          message: TextSpan(text: e.toString()),
        );
      }
    }
  }

  Future<FileInfo> _getGeoFileLastModified(String fileName) async {
    final homePath = await appPath.homeDirPath;
    final file = File(join(homePath, fileName));
    final lastModified = await file.lastModified();
    final size = await file.length();
    return FileInfo(size: size, lastModified: lastModified);
  }

  Widget _buildSubtitle() {
    return Consumer(
      builder: (context, ref, _) {
        final appLocalizations = context.appLocalizations;
        final url = ref.watch(
          patchClashConfigProvider.select(
            (state) => state.geoXUrl[widget.type],
          ),
        );
        if (url == null) {
          return const SizedBox();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            FutureBuilder<FileInfo>(
              future: _getGeoFileLastModified(fileName),
              builder: (_, snapshot) {
                final height = globalState.measure.bodyMediumHeight;
                return SizedBox(
                  height: height,
                  child: snapshot.data == null
                      ? SizedBox(width: height, height: height)
                      : Text(
                          snapshot.data!.getDesc(context),
                          style: context.textTheme.bodyMedium,
                        ),
                );
              },
            ),
            const SizedBox(height: 4),
            Text(url, style: context.textTheme.bodyMedium?.toLight),
            const SizedBox(height: 12),
            Wrap(
              runSpacing: 6,
              spacing: 12,
              runAlignment: WrapAlignment.center,
              children: [
                CommonChip(
                  avatar: const Icon(Icons.edit),
                  label: appLocalizations.edit,
                  onPressed: () {
                    _updateUrl(url, ref);
                  },
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      child: ValueListenableBuilder(
                        valueListenable: isUpdating,
                        builder: (_, isUpdating, _) {
                          return isUpdating
                              ? const SizedBox(
                                  height: 30,
                                  width: 30,
                                  child: Padding(
                                    padding: EdgeInsets.all(2),
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              : CommonChip(
                                  avatar: const Icon(Icons.sync),
                                  label: appLocalizations.sync,
                                  onPressed: () {
                                    _handleUpdateGeoDataItem();
                                  },
                                );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
        );
      },
    );
  }

  Future<void> _handleUpdateGeoDataItem() async {
    await globalState.safeRun<void>(() async {
      await updateGeoDateItem();
    }, silence: false);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> updateGeoDateItem() async {
    isUpdating.value = true;
    try {
      final message = await coreController.updateGeoData(label);
      if (message.isNotEmpty) throw message;
    } catch (e) {
      isUpdating.value = false;
      rethrow;
    }
    isUpdating.value = false;
    return;
  }

  @override
  void dispose() {
    super.dispose();
    isUpdating.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListItem(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(label),
      subtitle: _buildSubtitle(),
    );
  }
}

class UpdateGeoUrlFormDialog extends StatefulWidget {
  final String title;
  final String url;
  final String? defaultValue;

  const UpdateGeoUrlFormDialog({
    super.key,
    required this.title,
    required this.url,
    this.defaultValue,
  });

  @override
  State<UpdateGeoUrlFormDialog> createState() => _UpdateGeoUrlFormDialogState();
}

class _UpdateGeoUrlFormDialogState extends State<UpdateGeoUrlFormDialog> {
  late final TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.url);
  }

  Future<void> _handleReset() async {
    if (widget.defaultValue == null) {
      return;
    }
    Navigator.of(context).pop<String>(widget.defaultValue);
  }

  Future<void> _handleUpdate() async {
    final url = _urlController.value.text;
    if (url.isEmpty) return;
    Navigator.of(context).pop<String>(url);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonDialog(
      title: widget.title,
      actions: [
        if (widget.defaultValue != null &&
            _urlController.value.text != widget.defaultValue) ...[
          TextButton(
            onPressed: _handleReset,
            child: Text(appLocalizations.reset),
          ),
          const SizedBox(width: 4),
        ],
        TextButton(
          onPressed: _handleUpdate,
          child: Text(appLocalizations.submit),
        ),
      ],
      child: Wrap(
        runSpacing: 16,
        children: [
          TextField(
            maxLines: 5,
            minLines: 1,
            controller: _urlController,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ],
      ),
    );
  }
}
