import 'dart:async';

import 'package:doodle_battle/core/crash_reporting.dart';
import 'package:doodle_battle/data/app_settings.dart';
import 'package:doodle_battle/data/backend/backend_api.dart';
import 'package:doodle_battle/domain/battle/battle.dart';
import 'package:doodle_battle/domain/drawing_analysis_result.dart';
import 'package:doodle_battle/domain/element_type.dart';
import 'package:doodle_battle/domain/stats.dart';
import 'package:doodle_battle/features/draw/drawing_services.dart';
import 'package:doodle_battle/features/drawing_analysis/drawing_analyzer.dart';
import 'package:doodle_battle/features/monetization/monetization_service.dart';
import 'package:doodle_battle/features/parental_gate/parental_gate.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

/// A tiny valid PNG (orange square).
Uint8List testPng() {
  final image = img.Image(width: 8, height: 8, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(255, 120, 0, 255));
  return Uint8List.fromList(img.encodePng(image));
}

DrawingAnalysisResult fakeAnalysis({
  double skill = 20,
  double energy = 80,
  ElementType element = ElementType.fire,
  Stats stats = const Stats(hp: 140, atk: 140, def: 120, spd: 130),
}) => DrawingAnalysisResult(
  cutoutPng: testPng(),
  imageHash: 'abc123',
  features: const {'inkCoverage': 0.3},
  energy: energy,
  skill: skill,
  element: element,
  baseStats: stats,
);

class FakeAnalyzer implements DrawingAnalyzerService {
  FakeAnalyzer({
    DrawingAnalysisResult? result,
    this.reject,
    this.undecodable = false,
  }) : result = result ?? fakeAnalysis();

  final DrawingAnalysisResult result;
  final DrawingRejectReason? reject;
  final bool undecodable;
  int calls = 0;

  @override
  Future<AnalysisOutcome> analyze(Uint8List imageBytes) async {
    calls++;
    if (undecodable) throw const UndecodableImageException();
    return AnalysisOutcome(result, rejectReason: reject);
  }
}

class FakeImageSource implements DrawingImageSource {
  FakeImageSource([Uint8List? bytes]) : bytes = bytes ?? testPng();
  final Uint8List? bytes;
  final picked = <PhotoSource>[];

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    picked.add(source);
    return bytes;
  }
}

/// Passes (or refuses) without UI.
class FakeGate implements ParentalGate {
  FakeGate({this.pass = true});
  bool pass;
  int calls = 0;

  @override
  Future<bool> verify(BuildContext context) async {
    calls++;
    return pass;
  }
}

/// Scriptable [MonetizationService] for widget tests.
class FakeMonetization extends ChangeNotifier implements MonetizationService {
  FakeMonetization({
    this.adResult = RewardedAdResult.rewarded,
    this.storeAvailable = true,
    this.adState = AdState.ready,
    Map<Product, String>? prices,
  }) : prices =
           prices ??
           {
             Product.slots24: '￥250',
             Product.framePack: '￥160',
             Product.noAdsPass: '￥320',
           };

  RewardedAdResult adResult;
  PurchaseResult purchaseResult = PurchaseResult.purchased;
  int adsShown = 0;
  int preloads = 0;
  int refreshes = 0;
  int restores = 0;
  final adsAllowedCalls = <bool>[];
  Set<Product>? startedWith;
  final purchases = <Product>[];
  final Map<Product, String> prices;
  final _entitlements = StreamController<Set<Product>>.broadcast();
  Set<Product> _owned = {};

  @override
  AdState adState;

  void setAdState(AdState s) {
    adState = s;
    notifyListeners();
  }

  /// Simulates the store reporting owned products.
  void emitOwned(Set<Product> owned) {
    _owned = owned;
    _entitlements.add(owned);
  }

  @override
  Future<void> start(Set<Product> cachedEntitlements) async {
    startedWith = cachedEntitlements;
    _owned = {..._owned, ...cachedEntitlements};
  }

  @override
  Future<void> setAdsAllowed(bool allowed) async =>
      adsAllowedCalls.add(allowed);

  @override
  bool get rewardedAdReady => adState == AdState.ready;

  @override
  Future<void> preloadRewardedAd() async => preloads++;

  @override
  Future<RewardedAdResult> showRewardedAd() async {
    adsShown++;
    return adResult;
  }

  @override
  bool storeAvailable;

  @override
  String? priceOf(Product product) => storeAvailable ? prices[product] : null;

  @override
  Future<void> refreshStore() async => refreshes++;

  @override
  Future<PurchaseResult> purchase(Product product) async {
    purchases.add(product);
    if (purchaseResult == PurchaseResult.purchased) {
      emitOwned({..._owned, product});
    }
    return purchaseResult;
  }

  @override
  Future<bool> restorePurchases() async {
    restores++;
    return true;
  }

  @override
  Set<Product> get owned => _owned;

  @override
  Stream<Set<Product>> get entitlements => _entitlements.stream;
}

/// Records consent changes.
class FakeCrashReporter implements CrashReporter {
  FakeCrashReporter({this.isAvailable = true});

  @override
  final bool isAvailable;
  final calls = <bool>[];

  @override
  Future<void> setEnabled(bool enabled) async => calls.add(enabled);
}

/// Scriptable [BackendApi].
class FakeBackend implements BackendApi {
  FakeBackend({this.available = true});

  final bool available;
  String? uid;
  final calls = <String>[];
  ParentConsents? lastConsent;
  CloudJudgement? judgement;
  Object? judgeError;
  final registerOutcomes = <RegisterOutcome>[];
  final queueResults = <QueueStatus>[];
  final matchController = StreamController<MatchSnapshot>.broadcast();
  final turnLogs = <int, List<BattleEvent>>{};
  final submitted = <(int, BattleAction)>[];
  final reports = <(String, ReportReason)>[];
  bool deleteFails = false;

  @override
  bool get isAvailable => available;

  @override
  String? get supportId => uid;

  @override
  Future<void> syncConsent(ParentConsents consents, int policyVersion) async {
    calls.add('syncConsent');
    uid ??= 'uid-1';
    lastConsent = consents;
  }

  @override
  Future<CloudJudgement> judgeDrawing(Uint8List cutoutPng) async {
    calls.add('judgeDrawing');
    if (judgeError != null) throw judgeError!;
    return judgement!;
  }

  @override
  Future<RegisterOutcome> registerCharacter(
    RegisterCharacterRequest request,
  ) async {
    calls.add('registerCharacter:${request.character.name}');
    return registerOutcomes.removeAt(0);
  }

  @override
  Future<QueueStatus> joinQueue(String snapshotId) async {
    calls.add('joinQueue');
    return queueResults.length > 1
        ? queueResults.removeAt(0)
        : queueResults.first;
  }

  @override
  Future<void> leaveQueue() async => calls.add('leaveQueue');

  @override
  Stream<MatchSnapshot> watchMatch(String matchId) => matchController.stream;

  @override
  Future<List<BattleEvent>> turnEvents(String matchId, int turn) async =>
      turnLogs[turn] ?? const [];

  @override
  Future<void> submitAction(
    String matchId,
    int turn,
    BattleAction action,
  ) async {
    submitted.add((turn, action));
  }

  @override
  Future<PollResult> pollMatch(String matchId) async {
    calls.add('pollMatch');
    return const PollResult(status: MatchStatus.active, turn: 1);
  }

  final displayNames = <(String, String)>[];
  Object? displayNameError;

  @override
  Future<ChosenDisplayName> setDisplayName(
    String adjectiveId,
    String nounId,
  ) async {
    calls.add('setDisplayName');
    if (displayNameError != null) throw displayNameError!;
    displayNames.add((adjectiveId, nounId));
    return ChosenDisplayName(
      adjectiveId: adjectiveId,
      nounId: nounId,
      text: '$adjectiveId $nounId',
    );
  }

  @override
  Future<bool> reportCharacter(String snapshotId, ReportReason reason) async {
    reports.add((snapshotId, reason));
    return false;
  }

  final aiReports = <(AiSuggestionKind, String, AiReportReason)>[];
  BackendException? aiReportError;

  @override
  Future<void> reportAiSuggestion(
    AiSuggestionKind kind,
    String text,
    AiReportReason reason,
  ) async {
    calls.add('reportAiSuggestion');
    if (aiReportError != null) throw aiReportError!;
    aiReports.add((kind, text, reason));
  }

  @override
  Future<Uint8List?> loadSnapshotImage(String imagePath) async => null;

  @override
  Future<void> deleteMyData() async {
    calls.add('deleteMyData');
    if (deleteFails) throw const BackendException(BackendCodes.network);
    uid = null;
  }
}
