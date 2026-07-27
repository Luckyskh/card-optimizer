/// Card Optimizer — which of your cards should you use for this purchase?
///
/// This file wires the app together: two tabs, the shared data objects they
/// both use, and the terms-change banner across the top.
///
/// Everything here runs offline. The only network call in the whole app is the
/// optional alerts download in `data/alerts_service.dart`, and the app works
/// fine without it.
library;

import 'package:flutter/material.dart';

import 'data/alerts_service.dart';
import 'data/rules_repository.dart';
import 'data/user_cards_store.dart';
import 'screens/my_cards_screen.dart';
import 'screens/recommend_screen.dart';
import 'widgets/alert_banner.dart';

void main() {
  runApp(const CardOptimizerApp());
}

/// A one-line "something changed, please reload" announcer.
///
/// Flutter's own [ChangeNotifier] keeps `notifyListeners` protected, so this
/// thin subclass exposes a public [bump] instead of us reaching past that.
class RefreshSignal extends ChangeNotifier {
  void bump() => notifyListeners();
}

class CardOptimizerApp extends StatelessWidget {
  const CardOptimizerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Card Optimizer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Created once and shared by both tabs, so the rules JSON is parsed a single
  // time and both screens see the same saved card list.
  final _rulesRepository = RulesRepository();
  final _store = UserCardsStore();
  final _alertsService = AlertsService();

  /// Bumped whenever the user changes their cards, which tells the
  /// recommendation screen to reload.
  final _refreshSignal = RefreshSignal();

  int _tabIndex = 0;
  List<TermsAlert> _alerts = const [];

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  @override
  void dispose() {
    _refreshSignal.dispose();
    super.dispose();
  }

  Future<void> _loadAlerts() async {
    // Only show alerts about cards the user actually holds — a change to a
    // card they do not own is not their problem.
    final owned = await _store.ownedCardIds();
    final unseen = await _alertsService.unseen();
    if (!mounted) return;
    setState(() {
      _alerts =
          unseen.where((alert) => owned.contains(alert.cardId)).toList();
    });
  }

  Future<void> _dismissAlerts() async {
    await _alertsService.markAllSeen(_alerts.map((a) => a.id));
    if (!mounted) return;
    setState(() => _alerts = const []);
  }

  void _onCardsChanged() {
    _refreshSignal.bump();
    _loadAlerts();
  }

  @override
  Widget build(BuildContext context) {
    final alertedCardIds = _alerts.map((a) => a.cardId).toSet();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Card Optimizer'),
      ),
      body: Column(
        children: [
          AlertBanner(alerts: _alerts, onDismiss: _dismissAlerts),
          Expanded(
            child: IndexedStack(
              index: _tabIndex,
              children: [
                RecommendScreen(
                  rulesRepository: _rulesRepository,
                  store: _store,
                  refreshSignal: _refreshSignal,
                  alertedCardIds: alertedCardIds,
                ),
                MyCardsScreen(
                  rulesRepository: _rulesRepository,
                  store: _store,
                  onChanged: _onCardsChanged,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search),
            label: 'Which card?',
          ),
          NavigationDestination(
            icon: Icon(Icons.credit_card),
            label: 'My cards',
          ),
        ],
      ),
    );
  }
}
