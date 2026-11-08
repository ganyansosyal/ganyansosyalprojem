import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'theme.dart';

/// Menüdeki "Hesabımı sil" satırı: onay -> (şifre) -> silme -> giriş ekranına döner.
Future<void> startDeleteAccount(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final done = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _DeleteDialog(),
  );
  if (done == true) messenger?.showSnackBar(const SnackBar(content: Text('Hesabın silindi.')));
}

enum _Phase { confirm, password, working }

class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog();

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  _Phase _phase = _Phase.confirm;
  final _pw = TextEditingController();
  String? _err;
  String _step = 'Hazırlanıyor';

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  void _next() {
    if (AuthService.usesPassword) {
      setState(() {
        _phase = _Phase.password;
        _err = null;
      });
    } else {
      _run();
    }
  }

  void _submitPassword() {
    final v = _pw.text;
    if (v.isEmpty) {
      setState(() => _err = 'Şifreni yaz.');
      return;
    }
    if (v.length < 6) {
      setState(() => _err = 'Şifre en az 6 karakter olmalı.');
      return;
    }
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _phase = _Phase.working;
      _err = null;
      _step = 'Kimlik doğrulanıyor';
    });
    try {
      await AuthService.deleteMyAccount(
        password: _pw.text,
        onStep: (s) {
          if (mounted) setState(() => _step = s);
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = AuthService.errorText(e);
        _phase = AuthService.usesPassword ? _Phase.password : _Phase.confirm;
      });
    }
  }

  Widget _btn(AppColors c, String t, VoidCallback onTap, {bool danger = false}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: danger ? BoxDecoration(color: c.red, borderRadius: BorderRadius.circular(16)) : softCard(c, radius: 16.0),
          child: Text(t, style: jakarta(15, FontWeight.w800, danger ? Colors.white : c.tx)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget body;
    switch (_phase) {
      case _Phase.confirm:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Hesabını sil', textAlign: TextAlign.center, style: jakarta(20, FontWeight.w800, c.tx)),
          const SizedBox(height: 10),
          Text(
            'Profilin, paylaşımların, yorumların, sohbet mesajların, bildirimlerin ve takip kayıtların kalıcı olarak silinir. Bu işlem geri alınamaz.',
            textAlign: TextAlign.center,
            style: jakarta(14.5, FontWeight.w500, c.mu).copyWith(height: 1.35),
          ),
          if (_err != null) ...[
            const SizedBox(height: 10),
            Text(_err!, textAlign: TextAlign.center, style: jakarta(13, FontWeight.w700, c.red)),
          ],
          const SizedBox(height: 20),
          Row(children: [
            _btn(c, 'Vazgeç', () => Navigator.of(context).pop(false)),
            const SizedBox(width: 12),
            _btn(c, 'Devam et', _next, danger: true),
          ]),
        ]);
        break;
      case _Phase.password:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Şifreni gir', textAlign: TextAlign.center, style: jakarta(20, FontWeight.w800, c.tx)),
          const SizedBox(height: 10),
          Text(
            'Silmeden önce hesabın sana ait olduğunu doğruluyoruz.',
            textAlign: TextAlign.center,
            style: jakarta(14.5, FontWeight.w500, c.mu).copyWith(height: 1.35),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _pw,
            obscureText: true,
            autofocus: true,
            onChanged: (_) {
              if (_err != null) setState(() => _err = null);
            },
            onSubmitted: (_) => _submitPassword(),
            style: jakarta(15, FontWeight.w600, c.tx),
            decoration: InputDecoration(
              hintText: 'Şifre',
              hintStyle: jakarta(15, FontWeight.w500, c.mu),
              filled: true,
              fillColor: c.sf2,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.ln)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.ln)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.ac, width: 1.5)),
            ),
          ),
          SizedBox(
            height: 28,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(_err ?? '', style: jakarta(13, FontWeight.w700, c.red)),
            ),
          ),
          Row(children: [
            _btn(c, 'Vazgeç', () => Navigator.of(context).pop(false)),
            const SizedBox(width: 12),
            _btn(c, 'Hesabımı sil', _submitPassword, danger: true),
          ]),
        ]);
        break;
      case _Phase.working:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3, color: c.red)),
          const SizedBox(height: 16),
          Text('Hesabın siliniyor', textAlign: TextAlign.center, style: jakarta(18, FontWeight.w800, c.tx)),
          const SizedBox(height: 6),
          Text(_step, textAlign: TextAlign.center, style: jakarta(14, FontWeight.w600, c.mu)),
          const SizedBox(height: 4),
          Text('Uygulamayı kapatma.', textAlign: TextAlign.center, style: jakarta(13, FontWeight.w500, c.mu)),
        ]);
        break;
    }
    return PopScope(
      canPop: _phase != _Phase.working,
      child: Dialog(
        backgroundColor: c.sf,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
          child: body,
        ),
      ),
    );
  }
}
