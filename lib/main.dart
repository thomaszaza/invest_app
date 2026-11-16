import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/notification_service.dart';
import 'services/price_service.dart';
import 'screens/positions_screen.dart';
import 'screens/watchlist_screen.dart';
import 'screens/performance_screen.dart';
import 'screens/portfolio_screen.dart';

export 'services/price_service.dart';
export 'services/alerts_service.dart';
export 'services/notification_service.dart';
export 'screens/instrument_detail_screen.dart';
export 'screens/forms_screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.implicit,
    ),
  );

  await NotificationService.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zaza Invest',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.white),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

/// ==========================================
/// UTILITAIRES : TRADUCTION D'ERREURS & UI
/// ==========================================

/// Traduit les erreurs brutes de Supabase et du réseau en messages clairs
String _getFriendlyErrorMessage(Object error) {
  if (error is AuthException) {
    final msg = error.message.toLowerCase();
    final code = (error.code ?? '').toLowerCase();

    if (msg.contains('invalid login credentials') ||
        code == 'invalid_credentials') {
      return 'Adresse e-mail ou mot de passe incorrect.';
    }
    if (msg.contains('email not confirmed') || code == 'email_not_confirmed') {
      return 'Ton adresse e-mail n\'est pas encore confirmée. Vérifie ta boîte mail (et tes spams).';
    }
    if (msg.contains('user already registered') ||
        msg.contains('already exists') ||
        code == 'user_already_exists') {
      return 'Un compte existe déjà avec cette adresse e-mail. Essaie de te connecter.';
    }
    if (msg.contains('password should be at least') ||
        code == 'weak_password') {
      return 'Le mot de passe est trop faible (6 caractères minimum requis).';
    }
    if (msg.contains('different from the old password') ||
        code == 'same_password') {
      return 'Le nouveau mot de passe doit être différent de l\'ancien.';
    }
    if (msg.contains('rate limit') ||
        msg.contains('too many requests') ||
        error.statusCode == '429' ||
        code.contains('rate_limit')) {
      return 'Trop de tentatives rapprochées. Patiente quelques minutes avant de réessayer.';
    }
    if (msg.contains('unable to validate email address') ||
        msg.contains('invalid format') ||
        code == 'validation_failed') {
      return 'Le format de l\'adresse e-mail n\'est pas valide.';
    }
    if (msg.contains('user not found') || code == 'user_not_found') {
      return 'Aucun compte n\'a été trouvé avec cette adresse e-mail.';
    }
    if (msg.contains('expired') || code == 'otp_expired') {
      return 'Le lien de sécurité a expiré. Demande un nouveau lien de réinitialisation.';
    }

    return 'Impossible de finaliser l\'opération (${error.message}).';
  }

  final raw = error.toString().toLowerCase();
  if (raw.contains('socketexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('network') ||
      raw.contains('clientexception')) {
    return 'Connexion impossible. Vérifie ta connexion Internet et réessaie.';
  }

  return 'Une erreur inattendue est survenue. Réessaie dans un instant.';
}

/// Vérifie rapidement le format d'un email
bool _isValidEmail(String email) {
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
}

/// Affiche une notification flottante moderne (style carte iOS / Dark UI)
void _showFloatingNotification(
  BuildContext context, {
  required String title,
  required String message,
  bool isError = false,
}) {
  final accentColor = isError ? Colors.redAccent : Colors.greenAccent;
  final icon = isError
      ? Icons.error_outline_rounded
      : Icons.check_circle_outline_rounded;

  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      duration: const Duration(seconds: 4),
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: accentColor.withOpacity(0.45),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accentColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Bannière d'alerte intégrée directement dans le formulaire
class _StatusBanner extends StatelessWidget {
  final String message;
  final bool isError;
  final VoidCallback? onClose;

  const _StatusBanner({
    required this.message,
    this.isError = true,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final color = isError ? const Color(0xFFFF5252) : Colors.greenAccent;
    final icon = isError
        ? Icons.warning_amber_rounded
        : Icons.check_circle_outline_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError ? const Color(0xFFFFCDD2) : Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
          if (onClose != null)
            GestureDetector(
              onTap: onClose,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.close_rounded,
                  color: color.withOpacity(0.8),
                  size: 18,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Widget qui écoute l'état de l'authentification en temps réel
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isPasswordRecovery = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final currentEvent = snapshot.data?.event;

        if (currentEvent == AuthChangeEvent.passwordRecovery) {
          _isPasswordRecovery = true;
        } else if (currentEvent == AuthChangeEvent.signedOut) {
          _isPasswordRecovery = false;
        }

        if (_isPasswordRecovery) {
          return UpdatePasswordScreen(
            onPasswordUpdated: () {
              setState(() {
                _isPasswordRecovery = false;
              });
            },
          );
        }

        final session =
            snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;

        if (session != null) {
          return const MainNavigationScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}

/// ==========================================
/// ÉCRAN DE CONNEXION / INSCRIPTION
/// ==========================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isSignUp = false;
  bool _obscurePassword = true;

  // États pour l'affichage élégant des erreurs / messages
  String? _emailError;
  String? _passwordError;
  String? _bannerMessage;
  bool _isBannerError = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _clearMessages() {
    if (_emailError != null ||
        _passwordError != null ||
        _bannerMessage != null) {
      setState(() {
        _emailError = null;
        _passwordError = null;
        _bannerMessage = null;
      });
    }
  }

  InputDecoration _buildInputDecoration({
    required String label,
    required IconData prefixIcon,
    String? errorText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey[400]),
      errorText: errorText,
      errorStyle: const TextStyle(
        color: Color(0xFFFF5252),
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
      ),
      filled: true,
      fillColor: Colors.grey[900],
      prefixIcon: Icon(
        prefixIcon,
        color: errorText != null ? const Color(0xFFFF5252) : Colors.grey,
      ),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Colors.greenAccent,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(0xFFFF5252),
          width: 1.2,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(0xFFFF5252),
          width: 1.5,
        ),
      ),
    );
  }

  Future<void> _authenticate() async {
    FocusScope.of(context).unfocus();
    _clearMessages();

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // 1. Validation locale avant d'interroger Supabase
    bool hasValidationError = false;
    if (email.isEmpty) {
      _emailError = 'Entre ton adresse e-mail.';
      hasValidationError = true;
    } else if (!_isValidEmail(email)) {
      _emailError = 'Le format de l\'adresse e-mail est invalide.';
      hasValidationError = true;
    }

    if (password.isEmpty) {
      _passwordError = 'Entre ton mot de passe.';
      hasValidationError = true;
    } else if (_isSignUp && password.length < 6) {
      _passwordError = 'Le mot de passe doit contenir au moins 6 caractères.';
      hasValidationError = true;
    }

    if (hasValidationError) {
      setState(() {});
      return;
    }

    // 2. Appel Supabase
    setState(() => _isLoading = true);
    try {
      if (_isSignUp) {
        await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
        );
        if (mounted) {
          setState(() {
            _isBannerError = false;
            _bannerMessage =
                'Compte créé avec succès ! Vérifie ta boîte mail si une confirmation est requise, ou connecte-toi.';
          });
        }
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }
    } catch (e) {
      if (mounted) {
        final friendlyMsg = _getFriendlyErrorMessage(e);
        setState(() {
          _isBannerError = true;
          _bannerMessage = friendlyMsg;

          // Si le mot de passe ou l'email est incorrect, on souligne aussi les champs
          if (e is AuthException &&
              (e.message.toLowerCase().contains('invalid login credentials') ||
                  e.code == 'invalid_credentials')) {
            _passwordError = 'Vérifie ton mot de passe ou ton e-mail.';
          }
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    FocusScope.of(context).unfocus();

    final resetEmailController = TextEditingController(
      text: _emailController.text.trim(),
    );
    String? dialogEmailError;

    final String? emailToReset = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1C1C1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withOpacity(0.08)),
              ),
              title: const Row(
                children: [
                  Icon(Icons.lock_reset_rounded, color: Colors.greenAccent),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Mot de passe oublié',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Entre ton adresse e-mail pour recevoir un lien de réinitialisation :',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: resetEmailController,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    onChanged: (_) {
                      if (dialogEmailError != null) {
                        setDialogState(() => dialogEmailError = null);
                      }
                    },
                    decoration: _buildInputDecoration(
                      label: 'Email',
                      prefixIcon: Icons.email_outlined,
                      errorText: dialogEmailError,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text(
                    'Annuler',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    final input = resetEmailController.text.trim();
                    if (input.isEmpty) {
                      setDialogState(() {
                        dialogEmailError = 'Renseigne ton adresse e-mail.';
                      });
                      return;
                    }
                    if (!_isValidEmail(input)) {
                      setDialogState(() {
                        dialogEmailError = 'Format d\'e-mail invalide.';
                      });
                      return;
                    }
                    Navigator.pop(ctx, input);
                  },
                  child: const Text(
                    'Envoyer',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (emailToReset == null || emailToReset.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        emailToReset,
        redirectTo: 'https://thomaszaza.github.io/invest_app/',
      );
      if (mounted) {
        _showFloatingNotification(
          context,
          title: 'Lien envoyé !',
          message:
              'Vérifie ta boîte mail ($emailToReset) ainsi que tes spams.',
          isError: false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isBannerError = true;
          _bannerMessage = _getFriendlyErrorMessage(e);
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          _isSignUp ? 'Créer un compte' : 'Connexion',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.account_balance_wallet,
                    size: 64,
                    color: Colors.greenAccent,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Zaza Invest',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isSignUp
                        ? 'Inscris-toi pour suivre ton portefeuille'
                        : 'Bon retour ! Connecte-toi à ton espace',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                  const SizedBox(height: 36),

                  // Champ Email
                  TextField(
                    controller: _emailController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => _clearMessages(),
                    decoration: _buildInputDecoration(
                      label: 'Email',
                      prefixIcon: Icons.email_outlined,
                      errorText: _emailError,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Champ Mot de passe avec bouton Afficher/Masquer
                  TextField(
                    controller: _passwordController,
                    style: const TextStyle(color: Colors.white),
                    obscureText: _obscurePassword,
                    onChanged: (_) => _clearMessages(),
                    onSubmitted: (_) => _isLoading ? null : _authenticate(),
                    decoration: _buildInputDecoration(
                      label: 'Mot de passe',
                      prefixIcon: Icons.lock_outline,
                      errorText: _passwordError,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: Colors.grey[500],
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                    ),
                  ),

                  // Bannière d'erreur ou de confirmation animée
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    child: _bannerMessage != null
                        ? Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: _StatusBanner(
                              message: _bannerMessage!,
                              isError: _isBannerError,
                              onClose: () =>
                                  setState(() => _bannerMessage = null),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),

                  if (!_isSignUp) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _isLoading ? null : _resetPassword,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 12,
                          ),
                        ),
                        child: Text(
                          'Mot de passe oublié ?',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 13,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ] else
                    const SizedBox(height: 28),

                  // Bouton Principal
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _authenticate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.black,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              _isSignUp ? 'Créer mon compte' : 'Se connecter',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Bascule Connexion / Inscription
                  TextButton(
                    onPressed: () {
                      _clearMessages();
                      setState(() => _isSignUp = !_isSignUp);
                    },
                    child: Text(
                      _isSignUp
                          ? 'Déjà un compte ? Connecte-toi'
                          : 'Pas encore de compte ? Crée-en un',
                      style: const TextStyle(color: Colors.greenAccent),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ==========================================
/// BARRE DE NAVIGATION PRINCIPALE
/// ==========================================
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const PositionsScreen(),
    const WatchlistScreen(),
    const PerformanceScreen(),
    const PortfolioScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        backgroundColor: const Color.fromARGB(255, 26, 26, 26),
        unselectedItemColor: const Color.fromARGB(255, 141, 139, 139),
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: const Color.fromARGB(255, 255, 255, 255),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: 'Positions',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.visibility),
            label: 'Watchlist',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.show_chart),
            label: 'Performance',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.pie_chart),
            label: 'Portfolio',
          ),
        ],
      ),
    );
  }
}

/// ==========================================
/// ÉCRAN DE RÉINITIALISATION DE MOT DE PASSE
/// ==========================================
class UpdatePasswordScreen extends StatefulWidget {
  final VoidCallback? onPasswordUpdated;

  const UpdatePasswordScreen({super.key, this.onPasswordUpdated});

  @override
  State<UpdatePasswordScreen> createState() => _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends State<UpdatePasswordScreen> {
  final _newPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  String? _fieldError;
  String? _bannerError;

  @override
  void dispose() {
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _fieldError = null;
      _bannerError = null;
    });

    final newPassword = _newPasswordController.text.trim();
    if (newPassword.isEmpty) {
      setState(() => _fieldError = 'Entre un nouveau mot de passe.');
      return;
    }
    if (newPassword.length < 6) {
      setState(
        () => _fieldError =
            'Le mot de passe doit contenir au moins 6 caractères.',
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      if (mounted) {
        _showFloatingNotification(
          context,
          title: 'Mot de passe mis à jour',
          message: 'Ton nouveau mot de passe est maintenant actif.',
          isError: false,
        );
        widget.onPasswordUpdated?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _bannerError = _getFriendlyErrorMessage(e);
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Nouveau mot de passe',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.lock_reset_rounded,
                  size: 56,
                  color: Colors.greenAccent,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Choisis ton nouveau mot de passe',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Utilise au moins 6 caractères pour sécuriser ton compte.',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _newPasswordController,
                  obscureText: _obscurePassword,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (_) {
                    if (_fieldError != null || _bannerError != null) {
                      setState(() {
                        _fieldError = null;
                        _bannerError = null;
                      });
                    }
                  },
                  onSubmitted: (_) => _isLoading ? null : _updatePassword(),
                  decoration: InputDecoration(
                    labelText: 'Nouveau mot de passe',
                    labelStyle: TextStyle(color: Colors.grey[400]),
                    errorText: _fieldError,
                    errorStyle: const TextStyle(
                      color: Color(0xFFFF5252),
                      fontSize: 12.5,
                    ),
                    filled: true,
                    fillColor: Colors.grey[900],
                    prefixIcon: Icon(
                      Icons.lock_outline,
                      color: _fieldError != null
                          ? const Color(0xFFFF5252)
                          : Colors.grey,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: Colors.grey[500],
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.greenAccent,
                        width: 1.5,
                      ),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFFFF5252),
                        width: 1.2,
                      ),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFFFF5252),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  child: _bannerError != null
                      ? Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: _StatusBanner(
                            message: _bannerError!,
                            isError: true,
                            onClose: () =>
                                setState(() => _bannerError = null),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _updatePassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Valider le nouveau mot de passe',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}