// ═════════════════════════════════════════════════════════════════════════
//  طبيبك — صفحة إنشاء الحساب وتسجيل الدخول بمفتاح المرور (بدون بريد وبدون OTP)
//
//  هذا الملف يحتوي الكود الجديد فقط (للمراجعة أو اللصق اليدوي في main.dart):
//   1) الجزء الأول (LoginScreen + _PasskeyOrb) يحل محل LoginScreen/_LoginState القديمين.
//   2) الجزء الثاني (requestSecurityPin + _PinSheet) يحل محل دالة requestSecurityPin القديمة.
//   3) في SplashScreen: onTap زر «لديك حساب؟» ← const LoginScreen(startWithSignIn: true)
//
//  يعتمد على ما هو موجود في main.dart: t(), kRed.., RedButton, AppField, Tap, glass, ring,
//  gTile, grad, chev, gap/gapW, HeartPainter, normPhone/fmtPhone/digitsFmt, app, Fb, home(), go(),
//  InfoScreen.terms()، و PasskeyAuthService / PasskeyAuthException (لم تتغيّر).
// ═════════════════════════════════════════════════════════════════════════

// ───────────────────────── إنشاء حساب / دخول بمفتاح المرور (بدون بريد وبدون رمز تحقق) ─────────────────────────
/// شاشة واحدة بوضعين: «حساب جديد» و«لدي حساب».
///  • حساب جديد: الاسم + رقم الهاتف (للتواصل فقط، لا يُرسل إليه شيء) ← PIN من 6 أرقام ← مفتاح المرور (بصمة / وجه / قفل الجهاز).
///  • الدخول: لمسة واحدة على مفتاح المرور ثم PIN — دون كتابة أي بيانات.
/// لا بريد إلكتروني، ولا رمز SMS، ولا كلمة مرور.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.startWithSignIn = false});

  /// true ← تُفتح الشاشة على وضع «لدي حساب» (مثلاً من زر «تسجيل الدخول» في الشاشة الأولى).
  final bool startWithSignIn;
  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  final ph = TextEditingController();
  final nm = TextEditingController();
  final passkey = PasskeyAuthService(app: 'tabebik_user');
  late bool signInMode = widget.startWithSignIn;
  String? nameErr, phoneErr, err;
  bool busy = false, done = false;
  String doneTitle = '', doneSub = '';

  @override
  void dispose() {
    ph.dispose();
    nm.dispose();
    passkey.close();
    super.dispose();
  }

  // ───── المنطق ─────
  void setMode(bool signIn) {
    if (busy || signIn == signInMode) return;
    FocusScope.of(context).unfocus();
    setState(() {
      signInMode = signIn;
      err = null;
      nameErr = null;
      phoneErr = null;
    });
  }

  /// لحظة نجاح قصيرة ثم الرئيسية.
  Future<void> celebrate(String title, String sub) async {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() {
      done = true;
      doneTitle = title;
      doneSub = sub;
    });
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) home(context);
  }

  Future<void> register() async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    final name = nm.text.trim();
    final phone = normPhone(ph.text);
    setState(() {
      nameErr = name.length < 3 ? 'اكتب اسمك (3 حروف على الأقل).' : null;
      phoneErr = phone == null ? 'أدخل رقم هاتف سوداني صحيح، مثل 912 345 678.' : null;
      err = null;
    });
    if (nameErr != null || phone == null) return;
    if (!Fb.on) {
      setState(() => err = 'لا يوجد اتصال بخدمة الحسابات. تأكد من الإنترنت ثم حاول مجدداً.');
      return;
    }
    setState(() => busy = true);
    try {
      // 1) PIN (مرتين)  2) إنشاء مفتاح المرور على الجهاز.
      final pin = await requestSecurityPin(context, confirm: true);
      if (pin.isEmpty) return; // أغلق المستخدم نافذة PIN ← لا نُنشئ شيئاً.
      await passkey.registerAccount(displayName: name, phone: phone, pin: pin);
      app.createAccount(phone, name);
      app.ping();
      await celebrate('تم إنشاء حسابك', 'أهلاً بك يا ${app.first}، لنبدأ رحلتك الصحية.');
    } catch (e) {
      if (mounted) setState(() => err = e is PasskeyAuthException ? e.message : 'تعذر إنشاء الحساب. تأكد من الإنترنت ومن تفعيل قفل الشاشة أو البصمة على جهازك.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> signIn() async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    if (!Fb.on) {
      setState(() => err = 'لا يوجد اتصال بخدمة الحسابات. تأكد من الإنترنت ثم حاول مجدداً.');
      return;
    }
    setState(() {
      busy = true;
      err = null;
    });
    try {
      // المفتاح نفسه يحدد الحساب؛ لا حاجة لكتابة رقم الهاتف.
      await passkey.signIn(requestPin: () {
        if (!mounted) return Future.value('');
        return requestSecurityPin(context);
      });
      final found = await app.afterSignIn();
      if (!found) {
        await Fb.signOut();
        throw const PasskeyAuthException('لم نعثر على ملف حسابك. اختر «حساب جديد» لإنشاء حساب، أو تواصل مع الدعم.');
      }
      await celebrate('أهلاً بعودتك', app.first);
    } catch (e) {
      if (mounted) setState(() => err = e is PasskeyAuthException ? e.message : 'تعذر تسجيل الدخول. اختر مفتاح المرور المرتبط بحسابك ثم أدخل الـ PIN.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ───── الواجهة ─────
  Widget hero(double h, bool compact) => AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        height: h,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(gradient: kGradient),
        child: Stack(children: [
          Positioned(top: -70, left: -50, child: ring(220, const Color(0x14FFFFFF))),
          Positioned(top: 30, right: -70, child: ring(170, const Color(0x0FFFFFFF))),
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 26),
                child: OverflowBox(
                  minHeight: 0,
                  maxHeight: 200,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: compact
                        ? Row(key: const ValueKey('compact'), mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 40, height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13)), child: SizedBox(width: 22, height: 20, child: CustomPaint(painter: HeartPainter()))),
                            gapW(10),
                            Text('طبيبك', style: t(24, c: Colors.white)),
                          ])
                        : Column(key: const ValueKey('full'), mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              width: 76,
                              height: 76,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 12))]),
                              child: SizedBox(width: 42, height: 38, child: CustomPaint(painter: HeartPainter())),
                            ),
                            gap(10),
                            Text('طبيبك', style: t(30, c: Colors.white, h: 1.2)),
                            Text('صحتك .. أولويتنا', style: t(13, w: FontWeight.w500, c: const Color(0xE6FFFFFF))),
                          ]),
                  ),
                ),
              ),
            ),
          ),
          if (Navigator.canPop(context)) Positioned(top: MediaQuery.of(context).padding.top + 8, left: 12, child: glass(const Icon(Icons.close_rounded, color: Colors.white, size: 22), () => Navigator.maybePop(context))),
        ]),
      );

  Widget modeTab(String text, IconData icon, bool on, VoidCallback tap) => Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: text,
          excludeSemantics: true,
          child: Tap(
            scale: .97,
            onTap: tap,
            child: SizedBox(
              height: 44,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 18, color: on ? kRed : kGrey),
                gapW(6),
                Text(text, style: t(13.5, c: on ? kRed : kGrey)),
              ]),
            ),
          ),
        ),
      );

  Widget modeToggle() => Container(
        height: 52,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: kChip, borderRadius: BorderRadius.circular(18)),
        child: Stack(children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: signInMode ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
            child: FractionallySizedBox(
              widthFactor: .5,
              heightFactor: 1,
              child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: const [BoxShadow(color: Color(0x1A1B2A4A), blurRadius: 10, offset: Offset(0, 3))])),
            ),
          ),
          Row(children: [
            modeTab('حساب جديد', Icons.person_add_alt_1_rounded, !signInMode, () => setMode(false)),
            modeTab('لدي حساب', Icons.fingerprint_rounded, signInMode, () => setMode(true)),
          ]),
        ]),
      );

  /// يؤكد للمستخدم أن الرقم مقروء صحيحاً، ويذكّره أنه للتواصل فقط.
  Widget phoneHint() {
    final p = normPhone(ph.text);
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 2),
      child: Row(children: [
        Icon(p != null ? Icons.check_circle_rounded : Icons.info_outline_rounded, size: 15, color: p != null ? kGreen : kGrey),
        gapW(6),
        if (p != null) ...[
          Text('سنتواصل معك على ', style: t(11.5, w: FontWeight.w500, c: kGrey)),
          Directionality(textDirection: TextDirection.ltr, child: Text(fmtPhone(p), style: t(11.5, c: kGreenDk))),
        ] else
          Expanded(child: Text('للتواصل فقط، ولن نرسل إليه أي رمز.', style: t(11.5, w: FontWeight.w500, c: kGrey))),
      ]),
    );
  }

  Widget flowStep(IconData i, String s, Color c, Color bg) => Expanded(
        child: Column(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: bg, shape: BoxShape.circle), child: Icon(i, color: c, size: 22)),
          gap(7),
          Text(s, textAlign: TextAlign.center, style: t(11.5, w: FontWeight.w600, c: kSub, h: 1.4)),
        ]),
      );

  Widget flowArrow() => Padding(padding: const EdgeInsets.only(top: 10), child: chev(const Color(0xFFC3CAD6), 20));

  /// خطوات حقيقية متسلسلة بنفس ترتيب ما سيحدث بعد الضغط على الزر.
  Widget howItWorks() => Container(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 14),
        decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(20)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          flowStep(Icons.person_rounded, 'اسمك ورقمك', kBlue, kBlueBg),
          flowArrow(),
          flowStep(Icons.lock_rounded, 'PIN من 6 أرقام', kOrange, kOrangeBg),
          flowArrow(),
          flowStep(Icons.fingerprint_rounded, 'بصمتك أو وجهك', kRed, kTint),
        ]),
      );

  Widget signUpBody() => Column(
        key: const ValueKey('up'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('أنشئ حسابك في دقيقة', style: t(21)),
          gap(5),
          Text('اسمك ورقم هاتفك فقط. لا بريد إلكتروني ولا رمز تحقق.', style: t(13, w: FontWeight.w500, c: kGrey, h: 1.6)),
          AppField('الاسم', controller: nm, hint: 'مثال: أحمد محمد علي', icon: Icons.person_outline_rounded, error: nameErr, onChanged: (_) => setState(() {
                nameErr = null;
                err = null;
              })),
          AppField('رقم الهاتف للتواصل', controller: ph, hint: '9XX XXX XXX', icon: Icons.phone_outlined, type: TextInputType.phone, ltr: true, prefixText: '+249  ', error: phoneErr, fmt: [digitsFmt, LengthLimitingTextInputFormatter(14)], onChanged: (_) => setState(() {
                phoneErr = null;
                err = null;
              })),
          phoneHint(),
          gap(18),
          howItWorks(),
          gap(10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.cloud_done_rounded, size: 15, color: kGrey)),
            gapW(6),
            Expanded(child: Text('يُحفظ مفتاحك في Google أو iCloud، فيرافقك إلى جهازك الجديد.', style: t(11.5, w: FontWeight.w500, c: kGrey, h: 1.6))),
          ]),
        ],
      );

  Widget signInBody() => Column(
        key: const ValueKey('in'),
        children: [
          _PasskeyOrb(busy: busy),
          gap(4),
          Text('أهلاً بعودتك', style: t(21)),
          gap(6),
          Text('اضغط الزر، اختر مفتاح المرور المحفوظ على جهازك وأكّد ببصمتك. لا حاجة لكتابة أي بيانات.', textAlign: TextAlign.center, style: t(13, w: FontWeight.w500, c: kGrey, h: 1.7)),
        ],
      );

  Widget errBox(String m) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: kTint, borderRadius: BorderRadius.circular(14), border: Border.all(color: kRed.withAlpha(60))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.error_outline_rounded, color: kRed, size: 18),
              gapW(8),
              Expanded(child: Text(m, style: t(12.5, w: FontWeight.w600, c: kRed, h: 1.5))),
            ]),
          ),
        ),
      );

  Widget footer() => Column(children: [
        Tap(
          onTap: busy ? null : () => home(context),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16), child: Text('المتابعة كزائر', style: t(13.5, c: kSub))),
        ),
        Tap(
          onTap: () => go(context, InfoScreen.terms()),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Text.rich(TextSpan(text: 'بالمتابعة أنت توافق على ', style: t(11.5, w: FontWeight.w500, c: kGrey), children: [TextSpan(text: 'الشروط والأحكام', style: t(11.5, c: kRed))])),
          ),
        ),
      ]);

  Widget sheetBody(double bottom) => ListView(
        padding: EdgeInsets.fromLTRB(22, 22, 22, bottom + 20),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          modeToggle(),
          gap(22),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              layoutBuilder: (cur, prev) => Stack(fit: StackFit.passthrough, alignment: Alignment.topCenter, children: [...prev, if (cur != null) cur]),
              child: signInMode ? signInBody() : signUpBody(),
            ),
          ),
          if (err != null) errBox(err!),
          gap(18),
          RedButton(
            signInMode ? 'الدخول بمفتاح المرور' : 'إنشاء الحساب',
            icon: Icons.fingerprint_rounded,
            height: 58,
            loading: busy,
            onTap: signInMode ? signIn : register,
          ),
          gap(6),
          footer(),
        ],
      );

  Widget successView() => Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutBack,
          builder: (_, v, child) => Opacity(opacity: v.clamp(0.0, 1.0).toDouble(), child: Transform.scale(scale: .6 + .4 * v, child: child)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(gradient: grad(kGreen), shape: BoxShape.circle, boxShadow: [BoxShadow(color: kGreen.withAlpha(90), blurRadius: 28, offset: const Offset(0, 12))]),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 52),
              ),
              gap(22),
              Text(doneTitle, textAlign: TextAlign.center, style: t(22)),
              gap(8),
              Text(doneSub, textAlign: TextAlign.center, style: t(13.5, w: FontWeight.w500, c: kGrey, h: 1.7)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // الهيدر ينكمش عند ظهور لوحة المفاتيح أو على الشاشات القصيرة ليبقى الحقلان والزر ظاهرين.
    final compact = mq.viewInsets.bottom > 0 || mq.size.height < 620;
    final heroH = mq.padding.top + (compact ? 92.0 : 190.0);
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(fit: StackFit.expand, children: [
        Positioned(top: 0, left: 0, right: 0, child: hero(heroH, compact)),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          top: heroH - 28,
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: done ? successView() : sheetBody(mq.padding.bottom),
          ),
        ),
      ]),
    );
  }
}

/// أيقونة البصمة النابضة (الحركة الوحيدة غير المرتبطة بلمسة المستخدم، وتتوقف إن كان «تقليل الحركة» مفعّلاً).
class _PasskeyOrb extends StatefulWidget {
  const _PasskeyOrb({this.busy = false});
  final bool busy;
  @override
  State<_PasskeyOrb> createState() => _PasskeyOrbState();
}

class _PasskeyOrbState extends State<_PasskeyOrb> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      c.stop();
    } else if (!c.isAnimating) {
      c.repeat();
    }
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Widget wave(double v) => Opacity(opacity: (1 - v).clamp(0.0, 1.0).toDouble(), child: Transform.scale(scale: .5 + v * .5, child: ring(150, const Color(0x26D9141E))));

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 150,
        height: 150,
        child: AnimatedBuilder(
          animation: c,
          builder: (_, child) => Stack(alignment: Alignment.center, children: [wave(c.value), wave((c.value + .5) % 1), child!]),
          child: Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: kGradient, borderRadius: BorderRadius.circular(28), boxShadow: kGlow),
            child: widget.busy ? const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)) : const Icon(Icons.fingerprint_rounded, color: Colors.white, size: 46),
          ),
        ),
      );
}

/// نافذة الـ PIN (6 أرقام) — تُطلب بعد مفتاح المرور. نفس التوقيع القديم، فلا يتغيّر استدعاؤها من PasskeyAuthService.
///  • confirm: true  ← إنشاء PIN جديد (إدخال مرتين + رفض الأرقام السهلة مثل 123456 و 000000).
///  • confirm: false ← إدخال PIN موجود (يُقفل تلقائياً عند اكتمال 6 أرقام).
/// ترجع PIN، أو نصاً فارغاً إن أغلقها المستخدم.
Future<String> requestSecurityPin(BuildContext context, {bool confirm = false}) async {
  final r = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    builder: (_) => _PinSheet(create: confirm),
  );
  return r ?? '';
}

class _PinSheet extends StatefulWidget {
  const _PinSheet({required this.create});
  final bool create;
  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> with SingleTickerProviderStateMixin {
  static const len = 6;
  late final AnimationController shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  String cur = '', first = '';
  bool confirming = false, locked = false;
  String? error;

  @override
  void dispose() {
    shake.dispose();
    super.dispose();
  }

  /// أرقام متطابقة (111111) أو متسلسلة (123456 / 654321).
  bool weak(String p) {
    if (RegExp(r'^(\d)\1+$').hasMatch(p)) return true;
    return '01234567890'.contains(p) || '09876543210'.contains(p);
  }

  // Tap يضيف اهتزازاً خفيفاً عند كل لمسة، فلا نكرره هنا.
  void press(String d) {
    if (locked || cur.length >= len) return;
    setState(() {
      cur += d;
      error = null;
    });
    if (cur.length == len) Future.delayed(const Duration(milliseconds: 160), submit);
  }

  void erase() {
    if (locked || cur.isEmpty) return;
    setState(() {
      cur = cur.substring(0, cur.length - 1);
      error = null;
    });
  }

  Future<void> reject(String m) async {
    locked = true;
    HapticFeedback.heavyImpact();
    setState(() => error = m);
    await shake.forward(from: 0);
    if (!mounted) return;
    setState(() {
      cur = '';
      locked = false;
    });
  }

  void submit() {
    if (!mounted || cur.length != len) return;
    if (!widget.create) {
      Navigator.pop(context, cur);
      return;
    }
    if (!confirming) {
      if (weak(cur)) {
        reject('هذا الرقم سهل التخمين. اختر أرقاماً غير متسلسلة وغير مكررة.');
        return;
      }
      setState(() {
        first = cur;
        cur = '';
        confirming = true;
      });
      return;
    }
    if (cur != first) {
      reject('الرقمان غير متطابقين. أعد إدخال الـ PIN نفسه.');
      return;
    }
    Navigator.pop(context, cur);
  }

  void restart() => setState(() {
        first = '';
        cur = '';
        confirming = false;
        error = null;
      });

  Widget numKey(String d) => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Semantics(
            button: true,
            label: d,
            excludeSemantics: true,
            child: Tap(
              scale: .92,
              onTap: () => press(d),
              child: Container(height: 58, alignment: Alignment.center, decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(18)), child: Text(d, style: t(25, w: FontWeight.w600))),
            ),
          ),
        ),
      );

  Widget eraseKey() => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Semantics(
            button: true,
            label: 'حذف الرقم الأخير',
            excludeSemantics: true,
            child: Tap(
              scale: .92,
              onTap: erase,
              child: Container(height: 58, alignment: Alignment.center, child: const Icon(Icons.backspace_outlined, color: kSub, size: 24)),
            ),
          ),
        ),
      );

  /// شريط خطوتين (إنشاء ← تأكيد) يظهر في وضع إنشاء PIN فقط.
  Widget steps() {
    final s = confirming ? 1 : 0;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < 2; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: s == i ? 26 : 8,
          height: 8,
          decoration: BoxDecoration(color: i <= s ? kRed : kLine, borderRadius: BorderRadius.circular(4)),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final create = widget.create;
    final bad = error != null;
    final title = !create ? 'أدخل الـ PIN' : (confirming ? 'أكّد الـ PIN' : 'أنشئ PIN لحسابك');
    final sub = !create ? 'الأرقام الستة التي اخترتها عند إنشاء الحساب.' : (confirming ? 'أعد إدخال الأرقام الستة نفسها.' : 'ستة أرقام تحمي حسابك بعد مفتاح المرور. احفظها جيداً.');
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 42, height: 4, decoration: BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(2))),
          gap(12),
          Row(children: [
            Semantics(
              button: true,
              label: 'إغلاق',
              excludeSemantics: true,
              child: Tap(
                onTap: () => Navigator.pop(context, ''),
                child: Container(width: 38, height: 38, decoration: const BoxDecoration(color: kChip, shape: BoxShape.circle), child: const Icon(Icons.close_rounded, color: kSub, size: 20)),
              ),
            ),
            const Spacer(),
            if (create) steps(),
            const Spacer(),
            const SizedBox(width: 38),
          ]),
          gap(10),
          gTile(Icons.lock_rounded, size: 58),
          gap(14),
          Text(title, style: t(20)),
          gap(6),
          Text(sub, textAlign: TextAlign.center, style: t(12.5, w: FontWeight.w500, c: kGrey, h: 1.6)),
          gap(22),
          Semantics(
            label: 'تم إدخال ${cur.length} من $len أرقام',
            child: AnimatedBuilder(
              animation: shake,
              builder: (_, child) => Transform.translate(offset: Offset(math.sin(shake.value * math.pi * 6) * 12 * (1 - shake.value), 0), child: child),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < len; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    margin: const EdgeInsets.symmetric(horizontal: 7),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < cur.length ? (bad ? kRed : kInk) : Colors.transparent,
                      border: Border.all(color: bad ? kRed : (i < cur.length ? kInk : const Color(0xFFC3CAD6)), width: 1.8),
                    ),
                  ),
              ]),
            ),
          ),
          // ارتفاع ثابت لسطر الخطأ حتى لا تقفز لوحة الأرقام عند ظهوره.
          SizedBox(height: 44, child: Center(child: Text(error ?? '', textAlign: TextAlign.center, style: t(12, c: kRed, h: 1.4)))),
          // لوحة الأرقام دائماً LTR (1 2 3 / 4 5 6 / 7 8 9) حتى في الواجهة العربية.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Column(children: [
              for (final r in const [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
              ])
                Row(children: [for (final d in r) numKey(d)]),
              Row(children: [const Expanded(child: SizedBox(height: 66)), numKey('0'), eraseKey()]),
            ]),
          ),
          if (create && confirming)
            Tap(
              onTap: restart,
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16), child: Text('تغيير الرقم', style: t(13, c: kRed))),
            ),
        ]),
      ),
    );
  }
}
