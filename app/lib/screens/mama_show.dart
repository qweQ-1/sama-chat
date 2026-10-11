import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models.dart';
import '../photo_to_mama.dart';
import '../store.dart';
import '../widgets.dart';

/// mama秀 编辑器：捏一个属于自己的虚拟形象。
class MamaShowScreen extends StatefulWidget {
  const MamaShowScreen({super.key});

  @override
  State<MamaShowScreen> createState() => _MamaShowScreenState();
}

class _MamaShowScreenState extends State<MamaShowScreen> {
  late MamaShowConfig _c;
  bool _saving = false;

  static const _hairNames = ['无', '短发', '中分', '双马尾', '呆毛', '爆炸头', '长直发', '丸子头'];
  static const _outfitNames = ['T恤', '连帽衫', '衬衫', '裙子', '西装', '条纹衫'];
  static const _accNames = ['无', '圆眼镜', '墨镜', '耳机', '猫耳', '蝴蝶结', '口罩'];

  @override
  void initState() {
    super.initState();
    final me = context.read<AppState>().me;
    _c = me?.mamaShow ?? const MamaShowConfig();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<AppState>().saveMamaShow(_c);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('mama秀已保存 ✓ 好友都能看到啦')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showError(context, '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 从照片一键生成（端侧分析，不上传照片）。
  Future<void> _fromPhoto() async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(source: ImageSource.gallery);
      if (x == null || !mounted) return;

      // 分析中提示
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(strokeWidth: 2.5),
              SizedBox(width: 16),
              Expanded(child: Text('正在分析照片…')),
            ],
          ),
        ),
      );

      try {
        final cfg = await generateMamaFromPhoto(x.path);
        if (!mounted) return;
        Navigator.pop(context); // 关分析框
        setState(() => _c = cfg);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✨ 已根据照片生成，可以继续微调哦'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } on MamaPhotoException catch (e) {
        if (!mounted) return;
        Navigator.pop(context);
        showError(context, e.message);
      } catch (e) {
        if (!mounted) return;
        Navigator.pop(context);
        showError(context, '分析失败：$e');
      }
    } catch (e) {
      if (mounted) showError(context, '选照片失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('mama秀'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存',
                    style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // 大预览
          Center(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 6)),
                ],
              ),
              child: MamaAvatar(config: _c, size: 180, ring: false),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text('捏一个你的专属形象',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ),
          // 从照片生成（仅移动端：桌面没有 ML Kit）
          if (!isDesktopPlatform) ...[
            const SizedBox(height: 12),
            Center(
              child: FilledButton.icon(
                onPressed: _fromPhoto,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('从照片生成'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF5B5BD6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text('照片只在手机上分析，不会上传',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            ),
          ],
          const SizedBox(height: 16),

          _label('肤色'),
          _dotRow(
            count: 5,
            selected: _c.skin,
            colors: const [
              Color(0xFFFFE3CF),
              Color(0xFFF3C9A4),
              Color(0xFFDCA26F),
              Color(0xFFAE7449),
              Color(0xFF82552F),
            ],
            onPick: (i) => setState(() => _c = _c.copyWith(skin: i)),
          ),

          _label('发型'),
          _previewRow(
            count: 8,
            selected: _c.hair,
            names: _hairNames,
            build: (i) => _c.copyWith(hair: i),
            onPick: (i) => setState(() => _c = _c.copyWith(hair: i)),
          ),

          _label('发色'),
          _dotRow(
            count: 6,
            selected: _c.hairColor,
            colors: const [
              Color(0xFF2E2A33),
              Color(0xFF6D4A2F),
              Color(0xFFE8C04E),
              Color(0xFFC94B3C),
              Color(0xFF4A6FBF),
              Color(0xFFE88BB5),
            ],
            onPick: (i) => setState(() => _c = _c.copyWith(hairColor: i)),
          ),

          _label('衣服'),
          _previewRow(
            count: 6,
            selected: _c.outfit,
            names: _outfitNames,
            build: (i) => _c.copyWith(outfit: i),
            onPick: (i) => setState(() => _c = _c.copyWith(outfit: i)),
          ),

          _label('衣服颜色'),
          _dotRow(
            count: 6,
            selected: _c.outfitColor,
            colors: const [
              Color(0xFFFFFFFF),
              Color(0xFF33333D),
              Color(0xFFE8574A),
              Color(0xFF4A7DE8),
              Color(0xFF43A867),
              Color(0xFFF2C14E),
            ],
            onPick: (i) => setState(() => _c = _c.copyWith(outfitColor: i)),
          ),

          _label('配饰'),
          _previewRow(
            count: 7,
            selected: _c.acc,
            names: _accNames,
            build: (i) => _c.copyWith(acc: i),
            onPick: (i) => setState(() => _c = _c.copyWith(acc: i)),
          ),

          _label('背景'),
          _bgRow(),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      );

  /// 颜色圆点选择行。
  Widget _dotRow({
    required int count,
    required int selected,
    required List<Color> colors,
    required void Function(int) onPick,
  }) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (ctx, i) {
          final sel = i == selected;
          return GestureDetector(
            onTap: () => onPick(i),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors[i],
                shape: BoxShape.circle,
                border: Border.all(
                  color: sel ? const Color(0xFF5B5BD6) : Colors.grey.shade300,
                  width: sel ? 3 : 1,
                ),
              ),
              child: sel
                  ? Icon(Icons.check,
                      size: 18,
                      color: colors[i].computeLuminance() > 0.6
                          ? Colors.black54
                          : Colors.white)
                  : null,
            ),
          );
        },
      ),
    );
  }

  /// 实时小预览选择行（发型/衣服/配饰）。
  Widget _previewRow({
    required int count,
    required int selected,
    required List<String> names,
    required MamaShowConfig Function(int) build,
    required void Function(int) onPick,
  }) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final sel = i == selected;
          return GestureDetector(
            onTap: () => onPick(i),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          sel ? const Color(0xFF5B5BD6) : Colors.grey.shade300,
                      width: sel ? 2.5 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: MamaAvatar(
                        config: build(i), size: 48, ring: false),
                  ),
                ),
                const SizedBox(height: 3),
                Text(names[i],
                    style: TextStyle(
                        fontSize: 10.5,
                        color: sel
                            ? const Color(0xFF5B5BD6)
                            : Colors.grey.shade500,
                        fontWeight:
                            sel ? FontWeight.w600 : FontWeight.normal)),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 背景选择（含「无」）。
  Widget _bgRow() {
    const bgColors = [
      Color(0xFFF2F2F7),
      Color(0xFFDCE8FF),
      Color(0xFFFFE1EC),
      Color(0xFFD8F3E3),
      Color(0xFFFFF0D1),
      Color(0xFFE9E1FF),
    ];
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (ctx, i) {
          final sel = i == _c.bg;
          return GestureDetector(
            onTap: () => setState(() => _c = _c.copyWith(bg: i)),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: bgColors[i],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: sel ? const Color(0xFF5B5BD6) : Colors.grey.shade300,
                  width: sel ? 3 : 1,
                ),
              ),
              child: sel
                  ? const Icon(Icons.check, size: 18, color: Color(0xFF5B5BD6))
                  : null,
            ),
          );
        },
      ),
    );
  }
}
