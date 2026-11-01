import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'theme.dart';

// TJK TV (Tay TV) resmi yayın adresleri. Yayın adresi değişirse yalnızca burası güncellenir.
const _liveUrls = [
  'https://tjktv-live.tjk.org/taytv/taytv.m3u8',
  'https://tjktv-live.tjk.org/taytv/taytv_480p.m3u8',
];

const _ac = Color(0xFF12B886);
const _amber = Color(0xFFFFB627);

/// Canlı yayını yatay tam ekran açar. Rota anında ve siyah açılır: geçiş animasyonu yok,
/// ekran dönerken beyaz parlama olmaz.
Future<void> showLive(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push<void>(PageRouteBuilder<void>(
    opaque: true,
    barrierColor: Colors.black,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (_, __, ___) => const _LivePage(),
  ));
}

class _Lv {
  final bool playing, wait;
  final double lag;
  const _Lv({this.playing = false, this.wait = true, this.lag = 0});
}

String _fmt(double t) {
  final s = t.floor().clamp(0, 999999);
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

class _LivePage extends StatefulWidget {
  const _LivePage();
  @override
  State<_LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<_LivePage> with WidgetsBindingObserver {
  VideoPlayerController? _v;
  final _st = ValueNotifier<_Lv>(const _Lv());
  final _muted = ValueNotifier<bool>(false);
  Timer? _t;
  bool _failed = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _open();
    _t = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _t?.cancel();
    _v?.dispose();
    _st.dispose();
    _muted.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // Uygulama arka plana gidince yayın sesi devam etmesin
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) _v?.pause();
  }

  // Önce ana yayını, olmazsa 480p yayını dener.
  Future<void> _open() async {
    if (_failed) setState(() => _failed = false);
    final old = _v;
    _v = null;
    await old?.dispose();
    for (final url in _liveUrls) {
      final c = VideoPlayerController.networkUrl(
        Uri.parse(url),
        formatHint: VideoFormat.hls,
        httpHeaders: const {'Referer': 'https://www.tjk.org/', 'Origin': 'https://www.tjk.org'},
      );
      try {
        await c.initialize().timeout(const Duration(seconds: 15));
        if (!mounted) {
          await c.dispose();
          return;
        }
        await c.play();
        setState(() => _v = c);
        return;
      } catch (_) {
        await c.dispose();
      }
    }
    if (mounted) setState(() => _failed = true);
  }

  void _tick() {
    final c = _v;
    if (c == null || !mounted) return;
    final v = c.value;
    final dur = v.duration.inMilliseconds / 1000.0;
    final pos = v.position.inMilliseconds / 1000.0;
    final n = _Lv(
      playing: v.isPlaying || v.isBuffering,
      wait: !v.isInitialized || v.isBuffering,
      lag: dur > 1 ? (dur - pos).clamp(0, 1e9).toDouble() : 0,
    );
    final o = _st.value;
    // Değişmediyse bildirim gönderme: boşuna yeniden çizim olmasın
    if (o.playing != n.playing || o.wait != n.wait || (o.lag - n.lag).abs() >= 1) _st.value = n;
  }

  Future<void> _toggle() async {
    final c = _v;
    if (c == null) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      await c.play();
    }
    _tick();
  }

  Future<void> _seek(double dt) async {
    final c = _v;
    if (c == null) return;
    try {
      final d = c.value.duration.inMilliseconds / 1000.0;
      final cur = c.value.position.inMilliseconds / 1000.0;
      final to = (cur + dt).clamp(0, d > 1 ? d - 1 : cur + dt).toDouble();
      await c.seekTo(Duration(milliseconds: (to * 1000).round()));
      _tick();
    } catch (_) {}
  }

  Future<void> _edge() async {
    final c = _v;
    if (c == null) return;
    try {
      await c.seekTo(c.value.duration);
      await c.play();
      _tick();
    } catch (_) {}
  }

  Future<void> _mute() async {
    final c = _v;
    if (c == null) return;
    await c.setVolume(_muted.value ? 1.0 : 0.0);
    _muted.value = !_muted.value;
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  Widget _pill(String text, VoidCallback f) => GestureDetector(
        onTap: f,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(12)),
          child: Text(text, style: jakarta(13, FontWeight.w800, Colors.white)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = _v;
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(fit: StackFit.expand, children: [
        if (c != null)
          Center(
            child: AspectRatio(
              aspectRatio: c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9,
              child: RepaintBoundary(child: VideoPlayer(c)),
            ),
          ),
        if (c != null)
          _Overlay(st: _st, muted: _muted, onToggle: _toggle, onSeek: _seek, onMute: _mute, onEdge: _edge, onClose: _close)
        else
          Center(
            child: _failed
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('Yayına şu an ulaşılamıyor', style: jakarta(14, FontWeight.w700, Colors.white70)),
                    const SizedBox(height: 12),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      _pill('Tekrar dene', _open),
                      const SizedBox(width: 10),
                      _pill('Kapat', _close),
                    ]),
                  ])
                : const CircularProgressIndicator(color: _ac),
          ),
        if (c == null && !_failed)
          Positioned(
            left: 16,
            top: 12,
            child: SafeArea(child: _pill('✕ Kapat', _close)),
          ),
      ]),
    );
  }
}

/// Kontroller: dokununca görünür, 3 sn sonra gizlenir
class _Overlay extends StatefulWidget {
  final ValueNotifier<_Lv> st;
  final ValueNotifier<bool> muted;
  final VoidCallback onToggle, onMute, onEdge, onClose;
  final void Function(double) onSeek;
  const _Overlay({required this.st, required this.muted, required this.onToggle, required this.onSeek, required this.onMute, required this.onEdge, required this.onClose});
  @override
  State<_Overlay> createState() => _OverlayState();
}

class _OverlayState extends State<_Overlay> {
  bool _show = true;
  Timer? _h;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void dispose() {
    _h?.cancel();
    super.dispose();
  }

  void _arm() {
    _h?.cancel();
    _h = Timer(const Duration(milliseconds: 3200), () {
      if (mounted && widget.st.value.playing) setState(() => _show = false);
    });
  }

  void _tap() {
    setState(() => _show = !_show);
    if (_show) _arm();
  }

  Widget _small(Widget child, VoidCallback f) => GestureDetector(
        onTap: () {
          f();
          _arm();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_Lv>(
      valueListenable: widget.st,
      builder: (_, v, __) {
        final show = _show || !v.playing;
        final behind = v.lag > 5;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tap,
          child: SafeArea(
            child: Stack(children: [
              if (v.wait) const Center(child: CircularProgressIndicator(color: _ac)),
              if (show && !v.wait)
                Center(
                  child: GestureDetector(
                    onTap: () {
                      widget.onToggle();
                      _arm();
                    },
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: Icon(v.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 36),
                    ),
                  ),
                ),
              if (show)
                Positioned(
                  left: 12,
                  top: 10,
                  child: _small(Text('✕ Kapat', style: jakarta(13, FontWeight.w800, Colors.white)), widget.onClose),
                ),
              if (show)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: Row(children: [
                    _small(Text('↺ 10', style: jakarta(13, FontWeight.w800, Colors.white)), () => widget.onSeek(-10)),
                    const SizedBox(width: 8),
                    _small(Text('10 ↻', style: jakarta(13, FontWeight.w800, Colors.white)), () => widget.onSeek(10)),
                    const SizedBox(width: 12),
                    behind
                        ? _small(Text('● Canlıya dön  -${_fmt(v.lag)}', style: jakarta(13, FontWeight.w800, _amber)), widget.onEdge)
                        : Text('● CANLI', style: jakarta(13, FontWeight.w800, Colors.white)),
                    const Spacer(),
                    ValueListenableBuilder<bool>(
                      valueListenable: widget.muted,
                      builder: (_, m, __) => _small(Icon(m ? Icons.volume_off : Icons.volume_up, color: Colors.white, size: 20), widget.onMute),
                    ),
                  ]),
                ),
            ]),
          ),
        );
      },
    );
  }
}
