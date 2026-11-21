import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await MobileAds.instance.initialize();
  runApp(const DiamondQuizApp());
}

class DiamondQuizApp extends StatelessWidget {
  const DiamondQuizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Diamond Quiz',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E1A),
        primaryColor: const Color(0xFF00E5FF),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasData) {
            return MainNavigationScreen(user: snapshot.data!);
          }
          return const LoginScreen();
        },
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login Error: $e')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.diamond, size: 84, color: Color(0xFF00E5FF)),
              const SizedBox(height: 16),
              const Text('Diamond Quiz', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'Play quizzes, watch ads, invite friends & redeem diamonds via UPI!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 32),
              _loading
                  ? const CircularProgressIndicator()
                  : ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      ),
                      onPressed: _signInWithGoogle,
                      icon: const Icon(Icons.login),
                      label: const Text('Sign in with Google', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  final User user;
  const MainNavigationScreen({super.key, required this.user});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  int _tabIndex = 0;
  RewardedAd? _rewardedAd;
  bool _isAdReady = false;
  int _qIndex = 0;
  final TextEditingController _upiController = TextEditingController();
  final TextEditingController _referInputController = TextEditingController();

  final String _defaultRewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917';

  final List> _questions = [
    {'q': 'Which planet is known as the Red Planet?', 'options': ['Earth', 'Mars', 'Jupiter', 'Venus'], 'ans': 1},
    {'q': 'What is 15 + 27?', 'options': ['42', '32', '52', '40'], 'ans': 0},
    {'q': 'Which is the largest ocean on Earth?', 'options': ['Atlantic', 'Indian', 'Pacific', 'Arctic'], 'ans': 2},
    {'q': 'How many days are there in a leap year?', 'options': ['365', '366', '364', '360'], 'ans': 1},
    {'q': 'What is the capital of India?', 'options': ['Mumbai', 'Kolkata', 'New Delhi', 'Chennai'], 'ans': 2},
    {'q': 'Which gas do plants absorb?', 'options': ['Oxygen', 'Nitrogen', 'Carbon Dioxide', 'Hydrogen'], 'ans': 2},
    {'q': 'How many players are in a cricket team?', 'options': ['9', '10', '11', '12'], 'ans': 2},
    {'q': 'Which is the fastest land animal?', 'options': ['Lion', 'Cheetah', 'Tiger', 'Horse'], 'ans': 1},
  ];

  @override
  void initState() {
    super.initState();
    _ensureUserDoc();
    _loadRewardedAd(_defaultRewardedAdUnitId);
  }

  String _generateReferralCode(String uid) {
    final prefix = uid.substring(0, min(4, uid.length)).toUpperCase();
    final rand = Random().nextInt(9000) + 1000;
    return 'DQ$prefix$rand';
  }

  Future<void> _ensureUserDoc() async {
    final ref = _db.collection('users').doc(widget.user.uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'uid': widget.user.uid,
        'name': widget.user.displayName ?? 'Player',
        'email': widget.user.email ?? '',
        'diamonds': 0,
        'adsWatchedToday': 0,
        'referralCode': _generateReferralCode(widget.user.uid),
        'referredBy': '',
        'totalReferrals': 0,
        'lastDailyClaim': '',
        'isBanned': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  void _loadRewardedAd(String adUnitId) {
    RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() {
              _rewardedAd = ad;
              _isAdReady = true;
            });
          }
        },
        onAdFailedToLoad: (error) {
          if (mounted) setState(() => _isAdReady = false);
          Future.delayed(const Duration(seconds: 5), () => _loadRewardedAd(adUnitId));
        },
      ),
    );
  }

  void _showRewardedAd(int rewardPerAd, String adUnitId) {
    if (_rewardedAd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video ad is loading, wait 3 seconds...')),
      );
      _loadRewardedAd(adUnitId);
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        setState(() {
          _rewardedAd = null;
          _isAdReady = false;
        });
        _loadRewardedAd(adUnitId);
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        setState(() {
          _rewardedAd = null;
          _isAdReady = false;
        });
        _loadRewardedAd(adUnitId);
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) async {
        await _db.collection('users').doc(widget.user.uid).update({
          'diamonds': FieldValue.increment(rewardPerAd),
          'adsWatchedToday': FieldValue.increment(1),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('+$rewardPerAd Diamonds added!')),
          );
        }
      },
    );
  }

  Future<void> _claimDailyBonus(String lastClaimDate, int dailyBonus) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (lastClaimDate == today) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daily bonus already claimed today!')),
      );
      return;
    }
    await _db.collection('users').doc(widget.user.uid).update({
      'diamonds': FieldValue.increment(dailyBonus),
      'lastDailyClaim': today,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Daily Bonus: +$dailyBonus Diamonds!')),
      );
    }
  }

  Future<void> _applyReferralCode(String currentReferredBy, String myCode, int referralReward) async {
    final enteredCode = _referInputController.text.trim().toUpperCase();
    if (currentReferredBy.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Referral already used!')));
      return;
    }
    if (enteredCode.isEmpty || enteredCode == myCode) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid referral code!')));
      return;
    }

    final query = await _db.collection('users').where('referralCode', isEqualTo: enteredCode).limit(1).get();
    if (query.docs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid referral code!')));
      }
      return;
    }

    final referrerDoc = query.docs.first;
    await _db.collection('users').doc(referrerDoc.id).update({
      'diamonds': FieldValue.increment(referralReward),
      'totalReferrals': FieldValue.increment(1),
    });
    await _db.collection('users').doc(widget.user.uid).update({
      'diamonds': FieldValue.increment(referralReward),
      'referredBy': enteredCode,
    });

    _referInputController.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Both earned +$referralReward Diamonds!')),
      );
    }
  }

  Future<void> _submitWithdraw(int currentDiamonds, int minWithdraw) async {
    final upi = _upiController.text.trim();
    if (upi.isEmpty || !upi.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid UPI ID')));
      return;
    }
    if (currentDiamonds < minWithdraw) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Minimum $minWithdraw diamonds required!')),
      );
      return;
    }

    await _db.collection('users').doc(widget.user.uid).update({
      'diamonds': FieldValue.increment(-minWithdraw),
    });
    await _db.collection('withdrawals').add({
      'uid': widget.user.uid,
      'name': widget.user.displayName ?? 'Player',
      'email': widget.user.email ?? '',
      'upiId': upi,
      'diamonds': minWithdraw,
      'rupees': (minWithdraw / 100).toStringAsFixed(2),
      'status': 'Pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    _upiController.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Withdrawal submitted!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('settings').doc('global').snapshots(),
      builder: (context, settingsSnap) {
        final settings = settingsSnap.data?.data() as Map<String, dynamic>? ?? {};
        final int rewardPerAd = int.tryParse((settings['diamondsPerAd'] ?? 10).toString()) ?? 10;
        final int minWithdraw = int.tryParse((settings['minWithdrawDiamonds'] ?? 1000).toString()) ?? 1000;
        final int referralReward = int.tryParse((settings['referralDiamonds'] ?? 50).toString()) ?? 50;
        final int dailyBonus = int.tryParse((settings['dailyBonusDiamonds'] ?? 20).toString()) ?? 20;
        final String adUnitId = (settings['rewardedAdUnitId'] ?? _defaultRewardedAdUnitId).toString().isNotEmpty
            ? (settings['rewardedAdUnitId'] ?? _defaultRewardedAdUnitId).toString()
            : _defaultRewardedAdUnitId;
        final String notice = (settings['notice'] ?? '').toString();

        return StreamBuilder<DocumentSnapshot>(
          stream: _db.collection('users').doc(widget.user.uid).snapshots(),
          builder: (context, userSnap) {
            final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
            final int diamonds = int.tryParse((userData['diamonds'] ?? 0).toString()) ?? 0;
            final bool isBanned = userData['isBanned'] ?? false;
            final String myReferralCode = (userData['referralCode'] ?? 'LOADING').toString();
            final String referredBy = (userData['referredBy'] ?? '').toString();
            final int totalReferrals = int.tryParse((userData['totalReferrals'] ?? 0).toString()) ?? 0;
            final String lastDailyClaim = (userData['lastDailyClaim'] ?? '').toString();

            if (isBanned) {
              return const Scaffold(
                body: Center(
                  child: Text('Account suspended by Admin.', style: TextStyle(color: Colors.redAccent, fontSize: 16)),
                ),
              );
            }

            return Scaffold(
              appBar: AppBar(
                backgroundColor: const Color(0xFF131A2E),
                title: const Text('Diamond Quiz'),
                actions: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('💎 $diamonds', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E5FF))),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout),
                    onPressed: () async {
                      await GoogleSignIn().signOut();
                      await FirebaseAuth.instance.signOut();
                    },
                  ),
                ],
              ),
              body: IndexedStack(
                index: _tabIndex,
                children: [
                  _buildQuizTab(rewardPerAd, dailyBonus, lastDailyClaim, adUnitId, notice),
                  _buildReferTab(myReferralCode, referredBy, totalReferrals, referralReward),
                  _buildWalletTab(diamonds, minWithdraw),
                ],
              ),
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: _tabIndex,
                backgroundColor: const Color(0xFF131A2E),
                selectedItemColor: const Color(0xFF00E5FF),
                unselectedItemColor: Colors.white60,
                onTap: (i) => setState(() => _tabIndex = i),
                items: const [
                  BottomNavigationBarItem(icon: Icon(Icons.quiz), label: 'Quiz & Ads'),
                  BottomNavigationBarItem(icon: Icon(Icons.group_add), label: 'Refer'),
                  BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Wallet'),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQuizTab(int rewardPerAd, int dailyBonus, String lastDailyClaim, String adUnitId, String notice) {
    final currentQ = _questions[_qIndex];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notice.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
              child: Text('📢 $notice', style: const TextStyle(color: Colors.amber)),
            ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E2942),
              foregroundColor: const Color(0xFF00E5FF),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () => _claimDailyBonus(lastDailyClaim, dailyBonus),
            icon: const Icon(Icons.card_giftcard),
            label: Text('Daily Bonus (+$dailyBonus 💎)', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF131A2E), borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Solve Quiz & Watch Ad (+$rewardPerAd 💎)',
                    style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 13)),
                const SizedBox(height: 10),
                Text(currentQ['q'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ...List.generate(4, (idx) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E2942),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () {
                          if (idx == currentQ['ans']) {
                            setState(() => _qIndex = (_qIndex + 1) % _questions.length);
                            _showRewardedAd(rewardPerAd, adUnitId);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wrong answer!')));
                          }
                        },
                        child: Text(currentQ['options'][idx]),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _isAdReady ? const Color(0xFF00E5FF) : Colors.grey,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () => _showRewardedAd(rewardPerAd, adUnitId),
            icon: const Icon(Icons.play_circle_fill),
            label: Text(
              _isAdReady ? 'Watch Video Ad (+$rewardPerAd 💎)' : 'Loading Ad...',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReferTab(String myReferralCode, String referredBy, int totalReferrals, int referralReward) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: const Color(0xFF131A2E), b
