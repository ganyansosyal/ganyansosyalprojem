import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'auth_service.dart';
import 'coupon_view.dart';
import 'theme.dart';

const _ay = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];

String _fullStamp(int ts) {
  if (ts <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day} ${_ay[d.month - 1]} ${d.year} · ${two(d.hour)}:${two(d.minute)}';
}

/// Kupon görseli penceresi: önizleme + Paylaş (paylaşım menüsü) + İndir (galeriye kaydet).
Future<void> openCouponShare(
  BuildContext context, {
  required Map<String, dynamic> coupon,
  required String author,
  required Profile? profile,
  required int ts,
  required String text,
  required String postId,
  required String status,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.of(context).sf,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => _ShareSheet(coupon: coupon, author: author, profile: profile, ts: ts, text: text, postId: postId, status: status),
  );
}

class _ShareSheet extends StatefulWidget {
  final Map<String, dynamic> coupon;
  final String author, text, postId, status;
  final Profile? profile;
  final int ts;
  const _ShareSheet({required this.coupon, required this.author, required this.profile, required this.ts, required this.text, required this.postId, required this.status});

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _key = GlobalKey();
  bool _busy = false;
  String _msg = '';

  Future<File> _png() async {
    // Ekran çizimi bitsin (yazı tipleri / fotoğraf), sonra görüntüyü al
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final b = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 3);
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/ganyansosyal-kupon-${widget.postId}.png');
    await f.writeAsBytes(bd!.buffer.asUint8List(), flush: true);
    return f;
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      final f = await _png();
      final cp = widget.coupon;
      await Share.shareXFiles([XFile(f.path, mimeType: 'image/png')], text: '${widget.author} · ${cp['city'] ?? ''} ${cp['type'] ?? ''} kuponu');
    } catch (_) {
      if (mounted) setState(() => _msg = 'Paylaşılamadı, tekrar dene.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      final f = await _png();
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putImage(f.path, album: 'GanyanSosyal');
      if (mounted) setState(() => _msg = 'Kupon görseli galeriye kaydedildi ✓');
    } catch (_) {
      if (mounted) setState(() => _msg = 'Kaydedilemedi. Galeri iznini kontrol et.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 14, 10),
          child: Row(children: [
            Expanded(child: Text('Kupon görseli', style: jakarta(20, FontWeight.w800, c.tx))),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(width: 40, height: 40, decoration: BoxDecoration(color: c.sf2, borderRadius: BorderRadius.circular(13)), child: Icon(Icons.close, size: 20, color: c.tx)),
            ),
          ]),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: RepaintBoundary(
              key: _key,
              child: _ShareCard(coupon: widget.coupon, author: widget.author, profile: widget.profile, ts: widget.ts, text: widget.text, status: widget.status),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Row(children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _share,
                  style: FilledButton.styleFrom(backgroundColor: c.ac, foregroundColor: c.on, disabledBackgroundColor: c.ac.withAlpha(120), disabledForegroundColor: c.on, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  child: Text('Paylaş', style: jakarta(16, FontWeight.w800, c.on)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: _busy ? null : _save,
                  style: OutlinedButton.styleFrom(side: BorderSide(color: c.ln, width: 1.2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  child: Text('İndir', style: jakarta(16, FontWeight.w800, c.tx)),
                ),
              ),
            ),
          ]),
        ),
        SizedBox(
          height: 26,
          child: Center(child: Text(_msg, style: jakarta(12, FontWeight.w700, c.mu))),
        ),
      ]),
    );
  }
}

/// Görsele dönüşen kart: koyu temada bile hep açık renklerle çizilir.
class _ShareCard extends StatelessWidget {
  final Map<String, dynamic> coupon;
  final String author, text, status;
  final Profile? profile;
  final int ts;
  const _ShareCard({required this.coupon, required this.author, required this.profile, required this.ts, required this.text, required this.status});

  @override
  Widget build(BuildContext context) {
    const c = AppColors.light;
    final stripe = status == 'win' ? const Color(0xFF16A34A) : status == 'lose' ? c.red : c.gold;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        color: c.bg,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 92,
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0E9F73), Color(0xFF16B886)], begin: Alignment.centerLeft, end: Alignment.centerRight)),
            child: Stack(children: [
              Positioned(right: -30, top: -40, child: Container(width: 120, height: 120, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withAlpha(26)))),
              Positioned(right: 40, bottom: -50, child: Container(width: 90, height: 90, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withAlpha(20)))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('GanyanSosyal', style: jakarta(28, FontWeight.w800, Colors.white, ls: -1)),
                  const SizedBox(height: 4),
                  Text('TAHMİN ET  •  PAYLAŞ  •  KAZAN', style: jakarta(10.5, FontWeight.w800, Colors.white.withAlpha(235), ls: 1.6)),
                ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: softCard(c, radius: 18.0),
              child: Stack(children: [
                Positioned(left: 0, top: 0, bottom: 0, width: 4, child: ColoredBox(color: stripe)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Avatar(profile: profile, size: 44),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(author, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(15, FontWeight.w800, c.tx)),
                          Text(_fullStamp(ts), style: jakarta(11.5, FontWeight.w500, c.mu)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(text.isNotEmpty ? text : 'Yeni kuponum hazır.', style: jakarta(14, FontWeight.w700, c.tx)),
                    const SizedBox(height: 8),
                    CouponView(coupon, ts: ts, colors: c),
                  ]),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 14),
            child: Center(child: Text('GanyanSosyal · Tahmin et, paylaş, kazan', style: jakarta(11.5, FontWeight.w600, c.mu))),
          ),
        ]),
      ),
    );
  }
}
