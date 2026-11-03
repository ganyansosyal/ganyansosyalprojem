import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'predict.dart' show NoBadge;
import 'theme.dart';

class FilmRow {
  final int no;
  final String name;
  final String? gny;
  const FilmRow(this.no, this.name, this.gny);
}

const _bg = Color(0xFF0B0F17);
const _card = Color(0xFF161B26);
const _ac = Color(0xFF12B886);

/// Koşu filmini uygulama içinde açar (web'deki açılır pencerenin karşılığı).
Future<void> showRaceFilm(
  BuildContext context, {
  required String url,
  required int race,
  required String city,
  required String dateLabel,
  required List<FilmRow> rows,
  String? title,
  String? subtitle,
  String? badge,
  String? meName,
  String? meSub,
  Future<List<FilmRow>> Function()? loader,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
    backgroundColor: _bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _FilmSheet(url: url, race: race, city: city, dateLabel: dateLabel, rows: rows, title: title, subtitle: subtitle, badge: badge, meName: meName, meSub: meSub, loader: loader),
  );
}


/// Videoyu bir kez telefona indirir (aynı dosya en fazla 1 kez iner), oynatıcı yerelden oynatır.
/// Böylece oynatıcının aynı mp4'ü tekrar tekrar çekmesi (150-200 MB) engellenir.
/// İndirme başarısız olursa doğrudan ağdan oynatmaya düşer.
Future<VideoPlayerController> _filmController(String url) async {
  try {
    final dir = Directory('${(await getTemporaryDirectory()).path}/film_cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    // Eski videoları temizle: 1 günden eski veya 5'ten fazla dosya
    try {
      final fs = dir.listSync().whereType<File>().toList()..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      for (var i = 0; i < fs.length; i++) {
        if (i >= 5 || DateTime.now().difference(fs[i].lastModifiedSync()).inHours > 24) fs[i].deleteSync();
      }
    } catch (_) {}
    final name = '${url.hashCode.toUnsigned(32)}.mp4';
    final f = File('${dir.path}/$name');
    if (!f.existsSync() || f.lengthSync() < 1024) {
      final tmp = File('${f.path}.part');
      final c = http.Client();
      try {
        final res = await c.send(http.Request('GET', Uri.parse(url))).timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) throw 'http ${res.statusCode}';
        final sink = tmp.openWrite();
        await sink.addStream(res.stream.timeout(const Duration(seconds: 30)));
        await sink.close();
        await tmp.rename(f.path);
      } finally {
        c.close();
        if (tmp.existsSync()) tmp.deleteSync();
      }
    }
    return VideoPlayerController.file(f);
  } catch (_) {
    return VideoPlayerController.networkUrl(Uri.parse(url));
  }
}

/// Videoyu doğrudan YATAY TAM EKRANDA açar (alt panel yok). Kullanıcı kendisi kapatır.
/// Video hazır olunca açılır; hata olursa istisna fırlatır (çağıran yer mesaj gösterir).
Future<void> showFullVideo(BuildContext context, String url) async {
  final v = await _filmController(url);
  try {
    await v.initialize();
  } catch (e) {
    await v.dispose();
    rethrow;
  }
  if (!context.mounted) {
    await v.dispose();
    return;
  }
  await v.play();
  try {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _FullVideo(controller: v)));
  } finally {
    await v.pause();
    // Kapanış animasyonu bitmeden denetleyici silinmesin
    await Future.delayed(const Duration(milliseconds: 600));
    await v.dispose();
  }
}

class _FilmSheet extends StatefulWidget {
  final String url, city, dateLabel;
  final int race;
  final List<FilmRow> rows;
  final String? title, subtitle, badge, meName, meSub;
  final Future<List<FilmRow>> Function()? loader;
  const _FilmSheet({required this.url, required this.race, required this.city, required this.dateLabel, required this.rows, this.title, this.subtitle, this.badge, this.meName, this.meSub, this.loader});
  @override
  State<_FilmSheet> createState() => _FilmSheetState();
}

class _FilmSheetState extends State<_FilmSheet> {
  // Yer tutucu; asıl oynatıcı video indirilince (yerel dosyadan) oluşturulur
  VideoPlayerController _v = VideoPlayerController.networkUrl(Uri.parse('about:blank'));
  bool _dead = false;
  double _speed = 1;
  bool _err = false;
  List<FilmRow> _rows = const [];
  bool _ld = false, _fail = false;

  static String _nk(String x) => x.toUpperCase().replaceAll('İ', 'I').replaceAll('Ğ', 'G').replaceAll('Ü', 'U').replaceAll('Ş', 'S').replaceAll('Ö', 'O').replaceAll('Ç', 'C').replaceAll(RegExp(r'[^A-Z0-9]'), '');

  // Koşu sonucunu arka planda yükler; takılırsa kendiliğinden 2 kez daha dener
  Future<void> _load() async {
    setState(() {
      _ld = true;
      _fail = false;
    });
    for (var t = 0; t < 3; t++) {
      try {
        final l = await widget.loader!();
        if (!mounted) return;
        if (l.isEmpty) throw 'bos';
        setState(() {
          _rows = l;
          _ld = false;
        });
        return;
      } catch (_) {
        if (t < 2) await Future.delayed(Duration(milliseconds: t == 0 ? 1500 : 4000));
        if (!mounted) return;
      }
    }
    setState(() {
      _ld = false;
      _fail = true;
    });
  }

  @override
  void initState() {
    super.initState();
    _rows = widget.rows;
    if (widget.loader != null && _rows.isEmpty) _load();
    _start();
  }

  Future<void> _start() async {
    try {
      final c = await _filmController(widget.url);
      if (_dead) {
        await c.dispose();
        return;
      }
      final old = _v;
      _v = c;
      old.dispose();
      c.addListener(_tick);
      await c.initialize();
      if (!mounted) return;
      setState(() {});
      c.play();
    } catch (_) {
      if (mounted) setState(() => _err = true);
    }
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _dead = true;
    _v.removeListener(_tick);
    _v.dispose();
    super.dispose();
  }

  void _seek(int sec) {
    final p = _v.value.position + Duration(seconds: sec);
    final d = _v.value.duration;
    _v.seekTo(p < Duration.zero ? Duration.zero : (p > d ? d : p));
  }

  void _setSpeed(double s) {
    setState(() => _speed = s);
    _v.setPlaybackSpeed(s);
  }

  Future<void> _full() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _FullVideo(controller: _v)));
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes, s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ratio = _v.value.isInitialized ? _v.value.aspectRatio : 16 / 9;
    final land = MediaQuery.of(context).orientation == Orientation.landscape;
    final ok = _v.value.isInitialized;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Başlık
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: _ac, borderRadius: BorderRadius.circular(9)),
                child: Text(widget.badge ?? '${widget.race}', style: jakarta(15, FontWeight.w800, Colors.white)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.title ?? '${widget.city} · ${widget.race}. Koşu', maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(15, FontWeight.w800, Colors.white)),
                  Text(widget.subtitle ?? 'Koşu filmi · ${widget.dateLabel}', maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(11.5, FontWeight.w600, Colors.white54)),
                ]),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(color: Color(0xFF232A38), shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white70, size: 17),
                ),
              ),
            ]),
          ),
          // Video: yuvarlak köşeli, kenarlardan boşluklu, kontroller videonun üstünde
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * (land ? 0.5 : 0.27)),
                child: AspectRatio(
                  aspectRatio: ratio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      color: Colors.black,
                      child: _err
                          ? Center(child: Text('Video yüklenemedi.', style: jakarta(13, FontWeight.w600, Colors.white70)))
                          : !ok
                              ? const Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(color: _ac, strokeWidth: 2.5)))
                              : GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => setState(() => _v.value.isPlaying ? _v.pause() : _v.play()),
                                  child: Stack(fit: StackFit.expand, children: [
                                    VideoPlayer(_v),
                                    if (!_v.value.isPlaying)
                                      Center(
                                        child: Container(
                                          width: 50,
                                          height: 50,
                                          decoration: const BoxDecoration(color: Color(0x80000000), shape: BoxShape.circle),
                                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
                                        ),
                                      ),
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        padding: const EdgeInsets.fromLTRB(12, 14, 4, 0),
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xB3000000)]),
                                        ),
                                        child: Row(children: [
                                          Text('${_fmt(_v.value.position)} / ${_fmt(_v.value.duration)}', style: jakarta(11, FontWeight.w700, Colors.white70)),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: VideoProgressIndicator(
                                              _v,
                                              allowScrubbing: true,
                                              padding: const EdgeInsets.symmetric(vertical: 12),
                                              colors: const VideoProgressColors(playedColor: _ac, bufferedColor: Color(0x44FFFFFF), backgroundColor: Color(0x26FFFFFF)),
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: _full,
                                            child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.fullscreen_rounded, color: Colors.white, size: 22)),
                                          ),
                                        ]),
                                      ),
                                    ),
                                  ]),
                                ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Kontroller: küçük, tek satır
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(children: [
              _ib(Icons.replay_10_rounded, () => _seek(-10)),
              const SizedBox(width: 8),
              _ib(Icons.forward_10_rounded, () => _seek(10)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  for (final sp in const [0.5, 1.0, 2.0])
                    GestureDetector(
                      onTap: () => _setSpeed(sp),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                        decoration: BoxDecoration(color: _speed == sp ? _ac : Colors.transparent, borderRadius: BorderRadius.circular(9)),
                        child: Text('${sp == 1.0 ? '1' : sp == 2.0 ? '2' : '0.5'}x', style: jakarta(12.5, FontWeight.w800, _speed == sp ? Colors.white : Colors.white60)),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
          if (widget.meName != null) _me(),
          if (_ld)
            Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 6), child: Text('Koşu sonucu yükleniyor…', style: jakarta(13, FontWeight.w700, Colors.white60))),
          if (_fail)
            GestureDetector(
              onTap: _load,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                padding: const EdgeInsets.symmetric(vertical: 11),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
                child: Text('Koşu sonucu alınamadı · Tekrar dene', style: jakarta(13, FontWeight.w800, Colors.white70)),
              ),
            ),
          if (_rows.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('Koşu sonucu', style: jakarta(12.5, FontWeight.w700, Colors.white54)),
            ),
            for (var i = 0; i < _rows.length && i < 4; i++) _row(i, _rows[i]),
          ],
          const SizedBox(height: 14),
        ]),
      ),
    );
  }

  Widget _ib(IconData ic, VoidCallback f) => GestureDetector(
        onTap: f,
        child: Container(
          width: 38,
          height: 34,
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
          child: Icon(ic, color: Colors.white, size: 20),
        ),
      );

  Widget _me() {
    int? no;
    for (final r in _rows) {
      if (_nk(r.name) == _nk(widget.meName!)) no = r.no;
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFF241A45), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF5B3FB8))),
      child: Row(children: [
        if (no != null) ...[NoBadge(no, size: 30), const SizedBox(width: 10)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.meName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(14, FontWeight.w800, Colors.white)),
            if ((widget.meSub ?? '').isNotEmpty) Text(widget.meSub!, style: jakarta(11.5, FontWeight.w700, const Color(0xFFB9A7F5))),
          ]),
        ),
      ]),
    );
  }

  Widget _row(int i, FilmRow r) {
    const rk = [Color(0xFFF5C518), Color(0xFFC9D1DC), Color(0xFFD08B4B), Color(0xFF5B8DEF)];
    const lb = ['Kazandı', '2. oldu', '3. oldu', '4. oldu'];
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: i == 0 ? const Color(0xFF241F10) : _card,
        borderRadius: BorderRadius.circular(14),
        border: i == 0 ? Border.all(color: const Color(0xFF6B5A1E)) : (widget.meName != null && _nk(r.name) == _nk(widget.meName!) ? Border.all(color: const Color(0xFF5B3FB8)) : null),
      ),
      child: Row(children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: rk[i], shape: BoxShape.circle),
          child: Text('${i + 1}', style: jakarta(13, FontWeight.w800, const Color(0xFF111111))),
        ),
        const SizedBox(width: 8),
        NoBadge(r.no, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(13.5, FontWeight.w800, Colors.white)),
            Text(lb[i], style: jakarta(11.5, FontWeight.w700, rk[i])),
          ]),
        ),
        if (r.gny != null) Text('Ganyan ${r.gny}', style: jakarta(12.5, FontWeight.w800, const Color(0xFFFFB627))),
      ]),
    );
  }
}

class _FullVideo extends StatefulWidget {
  final VideoPlayerController controller;
  const _FullVideo({required this.controller});
  @override
  State<_FullVideo> createState() => _FullVideoState();
}

class _FullVideoState extends State<_FullVideo> {
  bool _show = true;
  Timer? _t;

  VideoPlayerController get _v => widget.controller;

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _v.addListener(_tick);
    _arm();
  }

  @override
  void dispose() {
    _t?.cancel();
    _v.removeListener(_tick);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // Butonlar oynarken 3 sn sonra kendiliğinden gizlenir
  void _arm() {
    _t?.cancel();
    _t = Timer(const Duration(seconds: 3), () {
      if (mounted && _v.value.isPlaying) setState(() => _show = false);
    });
  }

  void _toggleUi() {
    setState(() => _show = !_show);
    if (_show) _arm();
  }

  void _seek(int sec) {
    final p = _v.value.position + Duration(seconds: sec);
    final d = _v.value.duration;
    _v.seekTo(p < Duration.zero ? Duration.zero : (p > d ? d : p));
    _arm();
  }

  void _playPause() {
    _v.value.isPlaying ? _v.pause() : _v.play();
    _arm();
  }

  Widget _ib(IconData ic, VoidCallback f, {double size = 26, double pad = 10}) => GestureDetector(
        onTap: f,
        child: Container(
          padding: EdgeInsets.all(pad),
          decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
          child: Icon(ic, color: Colors.white, size: size),
        ),
      );

  Widget _chip(String t, VoidCallback f, {bool on = false}) => GestureDetector(
        onTap: f,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: on ? _ac : const Color(0x99000000), borderRadius: BorderRadius.circular(12)),
          child: Text(t, style: jakarta(13, FontWeight.w800, Colors.white)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final v = _v;
    final sp = v.value.playbackSpeed;
    return PopScope(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          // Videoya dokununca sadece butonlar açılır/kapanır, ekrandan çıkmaz
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleUi,
              child: Center(
                child: AspectRatio(aspectRatio: v.value.isInitialized ? v.value.aspectRatio : 16 / 9, child: VideoPlayer(v)),
              ),
            ),
          ),
          if (_show) ...[
            // Üst: kapat
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(children: [
                    _ib(Icons.fullscreen_exit, () => Navigator.pop(context)),
                    const Spacer(),
                    _ib(Icons.close, () => Navigator.pop(context)),
                  ]),
                ),
              ),
            ),
            // Orta: geri / oynat-duraklat / ileri
            Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _ib(Icons.replay_10, () => _seek(-10), size: 30),
                const SizedBox(width: 28),
                _ib(v.value.isPlaying ? Icons.pause : Icons.play_arrow, _playPause, size: 44, pad: 14),
                const SizedBox(width: 28),
                _ib(Icons.forward_10, () => _seek(10), size: 30),
              ]),
            ),
            // Alt: ilerleme + hız
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      for (final s in const [0.5, 1.0, 2.0]) ...[
                        _chip('${s == 1.0 ? '1' : s == 2.0 ? '2' : '0.5'}x', () {
                          v.setPlaybackSpeed(s);
                          _arm();
                        }, on: sp == s),
                        const SizedBox(width: 6),
                      ],
                    ]),
                    const SizedBox(height: 6),
                    VideoProgressIndicator(v, allowScrubbing: true, padding: const EdgeInsets.symmetric(vertical: 8), colors: const VideoProgressColors(playedColor: _ac)),
                  ]),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
