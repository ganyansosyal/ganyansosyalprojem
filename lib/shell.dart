import 'package:flutter/material.dart';
import 'admin.dart';
import 'auth_service.dart';
import 'feed.dart';
import 'leaders.dart';
import 'notifs.dart';
import 'profile.dart';
import 'chat.dart';
import 'coupon_banner.dart';
import 'extras.dart';
import 'predict.dart';
import 'preload.dart';
import 'results.dart';
import 'settle.dart';
import 'theme.dart';
import 'user_search.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final GlobalKey<ScaffoldState> _key = GlobalKey<ScaffoldState>();
  int _tab = 0;
  final Set<int> _built = {0};

  Widget _page(int i) {
    switch (i) {
      case 0:
        return FeedPage(
          onOpenRace: (city, race) {
            predictJump.value = (city: city, race: race);
            setState(() => _tab = 2);
          },
          onOpenLeaders: () => setState(() => _tab = 1),
        );
      case 1:
        return const LeadersPage();
      case 2:
        return PredictPage(active: _tab == 2, onShared: () => setState(() => _tab = 0));
      case 3:
        return const ResultsPage();
      default:
        return ProfileView(uid: profileNotifier.value?.uid ?? '');
    }
  }

  static const _titles = ['Akış', 'Liderler', 'Tahmin Yap', 'Sonuçlar', 'Profilim'];

  @override
  void initState() {
    super.initState();
    final u = profileNotifier.value?.uid ?? '';
    if (u.isNotEmpty) Settler.start(u);
    feedTarget.addListener(_toFeed);
  }

  // Bildirimden bir kupona gidilirken akış sekmesine geç
  void _toFeed() {
    if (feedTarget.value != null && mounted && _tab != 0) setState(() => _tab = 0);
  }

  @override
  void dispose() {
    feedTarget.removeListener(_toFeed);
    Settler.stop();
    super.dispose();
  }

  void _toast(String t) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    _built.add(_tab);
    return Scaffold(
      key: _key,
      resizeToAvoidBottomInset: false,
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                TopBar(
                  onMenu: () => _key.currentState?.openDrawer(),
                  onSearch: () => Navigator.push(context, UserSearchPage.route()),
                  onBell: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
                ),
                if (_tab == 0) const AnnounceTicker(),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 70 + bottom),
                    // Sekmeler bir kez kurulur, sonra canlı kalır (IndexedStack):
                    // sekme değiştirince baştan çizim ve yükleme ekranı olmaz.
                    child: Stack(children: [
                      IndexedStack(
                        index: _tab,
                        children: [for (var i = 0; i < 5; i++) _built.contains(i) ? _page(i) : const SizedBox.shrink()],
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Container(
                  padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + bottom),
                  decoration: BoxDecoration(
                    color: c.sf,
                    border: Border(top: BorderSide(color: c.ln)),
                    boxShadow: const [
                      BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, -2)),
                    ],
                  ),
                  child: Row(
                    children: [
                      _NavItem(icon: Icons.home_outlined, label: 'Akış', on: _tab == 0, onTap: () {
                        if (_tab == 0) {
                          feedScrollTop.value++;
                        } else {
                          setState(() => _tab = 0);
                        }
                      }),
                      _NavItem(icon: Icons.emoji_events_outlined, label: 'Liderler', on: _tab == 1, onTap: () => setState(() => _tab = 1)),
                      _NavItem(icon: Icons.format_list_bulleted, label: 'Tahmin Yap', on: _tab == 2, onTap: () => setState(() => _tab = 2)),
                      const SizedBox(width: 48),
                      _NavItem(icon: Icons.flag_outlined, label: 'Sonuçlar', on: _tab == 3, onTap: () => setState(() => _tab = 3)),
                      _NavItem(icon: Icons.person_outline, label: 'Profilim', on: _tab == 4, onTap: () => setState(() => _tab = 4)),
                      _NavItem(icon: Icons.power_settings_new, label: 'Çıkış', on: false, danger: true, onTap: () => confirmSignOut(context)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottom + 18,
            child: Center(
              child: GestureDetector(
                onTap: () => openChat(context),
                child: Container(
                  width: 46,
                  height: 46,
                  padding: const EdgeInsets.all(3.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.sf,
                    boxShadow: const [
                      BoxShadow(color: Color(0x26000000), blurRadius: 14, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF34D399), Color(0xFF0E9F73)],
                      ),
                    ),
                    child: const Icon(Icons.forum_rounded, color: Colors.white, size: 19),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: MediaQuery.paddingOf(context).top + 8,
            child: const CouponBanner(),
          ),
        ],
      ),
    );
  }
}

class TopBar extends StatelessWidget {
  final VoidCallback onMenu, onBell, onSearch;
  const TopBar({super.key, required this.onMenu, required this.onSearch, required this.onBell});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(bottom: BorderSide(color: c.ln.withAlpha(140))),
      ),
      child: Row(
        children: [
          IconBox(icon: Icons.menu, onTap: onMenu),
          const SizedBox(width: 10),
          GestureDetector(onLongPress: () => perfOverlay.value = !perfOverlay.value, child: const Brand(size: 19)),
          const SizedBox(width: 10),
          Expanded(
            // Yazı alanı değil, dokununca tam ekran arama sayfasını açan hap: ana sayfada klavye/odak sorunu kalmaz
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onSearch,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: c.sf,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.ln),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 18, color: c.ac),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Kullanıcı ara', maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(13, FontWeight.w600, c.mu))),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconBox(
            icon: isDark ? Icons.wb_sunny_outlined : Icons.dark_mode_outlined,
            onTap: () => themeMode.value = isDark ? ThemeMode.light : ThemeMode.dark,
          ),
          const SizedBox(width: 8),
          NotifBell(onTap: onBell),
        ],
      ),
    );
  }
}

class IconBox extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  const IconBox({super.key, required this.icon, required this.onTap, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c.sf,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.ln),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Icon(icon, size: 20, color: c.tx),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool on;
  final bool danger;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final fg = danger ? c.red : (on ? c.ac : c.mu);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: on
                    ? const LinearGradient(colors: [Color(0xFF34D399), Color(0xFF0E9F73)])
                    : null,
                boxShadow: on
                    ? const [BoxShadow(color: Color(0x6B0E9F73), blurRadius: 12, offset: Offset(0, 4))]
                    : null,
              ),
              child: Icon(icon, size: 22, color: on ? Colors.white : fg),
            ),
            const SizedBox(height: 3),
            Text(label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: jakarta(10.5, FontWeight.w700, fg)),
          ],
        ),
      ),
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  final String title;
  const PlaceholderPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: c.sf,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.ln),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: jakarta(22, FontWeight.w800, c.tx)),
            const SizedBox(height: 6),
            Text('Bu ekran sıradaki aşamada yapılacak.',
                textAlign: TextAlign.center,
                style: jakarta(14, FontWeight.w500, c.mu)),
          ],
        ),
      ),
    );
  }
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final me = profileNotifier.value;
    return Drawer(
      width: 300,
      backgroundColor: c.bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  const Brand(size: 24),
                  const Spacer(),
                  IconBox(icon: Icons.close, onTap: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () {
                  final u = profileNotifier.value?.uid;
                  Navigator.of(context).pop();
                  if (u != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileRoute(uid: u)));
                },
                child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(colors: [Color(0xFF14B27D), Color(0xFF0E9F73)]),
                ),
                child: Row(
                  children: [
                    Avatar(profile: me, size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(me?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(18, FontWeight.w800, Colors.white)),
                          Text('@${me?.handle ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(14, FontWeight.w600, const Color(0xE0FFFFFF))),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white),
                  ],
                ),
              ),
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: c.sf,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: c.ln),
                ),
                child: Column(
                  children: [
                    // Mağaza sadece yöneticiye görünür
                    if (isAdminNotifier.value) ...[
                      _DrawerRow(icon: Icons.diamond_outlined, label: 'Mağaza', onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShopPage()));
                      }),
                      Divider(height: 1, color: c.ln),
                    ],
                    _DrawerRow(icon: Icons.menu_book_outlined, label: 'Kurallar', onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RulesPage()));
                    }),
                    Divider(height: 1, color: c.ln),
                    _DrawerRow(
                      icon: Icons.wb_sunny_outlined,
                      label: 'Koyu tema',
                      onTap: () => themeMode.value = isDark ? ThemeMode.light : ThemeMode.dark,
                      trailing: Switch(
                        value: isDark,
                        activeColor: c.ac,
                        onChanged: (v) => themeMode.value = v ? ThemeMode.dark : ThemeMode.light,
                      ),
                    ),
                    if (isAdminNotifier.value) ...[
                      Divider(height: 1, color: c.ln),
                      _DrawerRow(icon: Icons.lock_outline, label: 'Yönetim paneli', onTap: () {
                        final nav = Navigator.of(context);
                        nav.pop();
                        showAdminPanel(nav.context);
                      }),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              Text('Hesabın ve paylaşımların bulutta saklanır.',
                  textAlign: TextAlign.center,
                  style: jakarta(13, FontWeight.w500, c.mu)),
              const SizedBox(height: 10),
              Divider(height: 1, color: c.ln),
              const SizedBox(height: 10),
              InkWell(
                onTap: () => confirmSignOut(context),
                borderRadius: BorderRadius.circular(14),
                child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: c.red.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.logout, color: c.red, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text('Oturumu kapat', style: jakarta(16, FontWeight.w700, c.red)),
                ],
              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  const _DrawerRow({required this.icon, required this.label, required this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: c.sf2, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 20, color: c.mu),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: jakarta(16, FontWeight.w700, c.tx))),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
