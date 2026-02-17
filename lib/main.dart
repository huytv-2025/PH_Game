import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final game = MazeGame();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      game.overlays.add('StartScreen');
      game.pauseEngine();
    });

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('vi', 'VN'),
        Locale('en', 'US'),
      ],
      home: GameWidget<MazeGame>(
        game: game,
        overlayBuilderMap: {
          'GameOver': (context, game) => GameOverOverlay(game: game),
          'PauseMenu': (context, game) => PauseMenuOverlay(game: game),
          'MathChallenge': (context, game) => MathChallengeOverlay(game: game),
          'StartScreen': (context, game) => StartScreenOverlay(game: game),
        },
      ),
    );
  }
}

class MazeGame extends FlameGame with HasCollisionDetection, TapCallbacks {
  Player? player;
  late TextComponent levelText;
  TextComponent? nameDisplay; // Làm thành biến để có thể remove khi reload
  HudButton? pauseButton;

  int currentLevel = 1;
  final int maxLevel = 10;
  bool isGameOver = false;

  final List<Bush> bushes = [];
  ExitPortal? exitPortal;

  bool isMathChallengeActive = false;
  MathChallenge? currentMathChallenge;

  double worldScrollSpeed = 180.0;

  String playerName = 'Người chơi';

  bool _isTouchingPortal = false;
  bool _hasTriggeredMathThisTouch = false;

  bool _waitingForBushesAfterMath = false;
  int _bushesPassedAfterMath = 0;
  final int _requiredBushesAfterMath = 3;
  final double _bushPassThreshold = -200.0;

  @override
  Color backgroundColor() => const Color(0xFF0D1B2A);

  @override
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);
    if (size.isZero()) return;

    if (currentLevel == 1 && bushes.isEmpty) {
      loadLevel(1);
    }
  }

  Future<void> loadLevel(int level) async {
    print('Bắt đầu load level $level - Tên hiện tại: $playerName');

    final toRemove = <Component>[];

    for (final c in children) {
      if (c is Bush || c is ExitPortal || c is HudButton || c is Player || c is TextComponent && (c.text.contains('Người chơi:') || c.text.contains('Màn'))) {
        toRemove.add(c);
      }
    }

    for (final c in toRemove) {
      remove(c);
    }

    bushes.clear();
    exitPortal = null;
    pauseButton = null;
    nameDisplay = null;

    pauseButton = HudButton(
      position: Vector2(size.x - 90, 90),
      onPressed: () {
        if (!isGameOver && !isMathChallengeActive) {
          pauseEngine();
          overlays.add('PauseMenu');
        }
      },
    );
    add(pauseButton!);

    levelText = TextComponent(
      text: 'Màn $level / $maxLevel',
      position: Vector2(size.x / 2, 100), // Tăng y lên để tránh bị che
      anchor: Anchor.center,
      textRenderer: TextPaint(
        style: const TextStyle(fontSize: 36, color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
    add(levelText);

    // Hiển thị tên người chơi thực tế - add sau cùng để đảm bảo cập nhật
    nameDisplay = TextComponent(
      text: 'Người chơi: $playerName',
      position: Vector2(20, 40),
      anchor: Anchor.topLeft,
      textRenderer: TextPaint(
        style: const TextStyle(
          fontSize: 28,
          color: Colors.cyanAccent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    add(nameDisplay!);
    print('Đã add nameDisplay: Người chơi: $playerName');

    generateObstacles(level);

    player = Player(position: Vector2(180, size.y / 2));
    await player!.onLoad();
    add(player!);

    exitPortal = ExitPortal(position: Vector2(size.x + 600, size.y / 2));
    await exitPortal!.onLoad();
    add(exitPortal!);

    isGameOver = false;
    isMathChallengeActive = false;
    _isTouchingPortal = false;
    _hasTriggeredMathThisTouch = false;
    _waitingForBushesAfterMath = false;
    _bushesPassedAfterMath = 0;

    worldScrollSpeed = 160.0 + (level - 3).clamp(0, 999) * 22.0;

    print('Level $level loaded - bushes: ${bushes.length} - speed: $worldScrollSpeed');
  }

  void generateObstacles(int level) {
    final random = math.Random();
    final double spacing = 320.0 - level * 20.0;
    double gapSize = 220.0 - (level * 10.0).clamp(0.0, 120.0);
    int columns = (size.x / spacing).ceil() + 5 + level;

    for (int i = 0; i < columns; i++) {
      double x = size.x + i * spacing + random.nextDouble() * 100;
      double gapY = 100 + random.nextDouble() * (size.y - 200 - gapSize);

      bushes.add(Bush(Vector2(x, gapY - gapSize / 2 - 80)));
      bushes.add(Bush(Vector2(x, gapY + gapSize / 2 + 80)));

      if (level > 3 && random.nextBool()) {
        bushes.add(Bush(Vector2(x + spacing / 2, gapY + random.nextDouble() * 100 - 50)));
      }
    }

    bushes.forEach(add);
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (isGameOver || isMathChallengeActive) return;

    bool shouldAddMoreBushes = false;

    for (final bush in bushes) {
      bush.position.x -= worldScrollSpeed * dt;

      if (_waitingForBushesAfterMath && player != null) {
        if (bush.position.x + bush.size.x / 2 < player!.position.x + _bushPassThreshold) {
          if (!bush.hasBeenPassedAfterMath) {
            bush.hasBeenPassedAfterMath = true;
            _bushesPassedAfterMath++;
            if (_bushesPassedAfterMath >= _requiredBushesAfterMath) {
              _waitingForBushesAfterMath = false;
              _bushesPassedAfterMath = 0;
              currentLevel++;
              final extraSpeed = (currentLevel >= 4) ? 18.0 + (currentLevel - 3) * 8.0 : 0.0;
              worldScrollSpeed += extraSpeed;
              levelText.text = 'Màn $currentLevel / $maxLevel';
              shouldAddMoreBushes = true;
            }
          }
        }
      }

      if (bush.position.x < -150) {
        bush.position.x = size.x + 150 + math.Random().nextDouble() * 250;
        bush.position.y = 60 + math.Random().nextDouble() * (size.y - 120);
        bush.hasBeenPassedAfterMath = false;
      }
    }

    if (shouldAddMoreBushes) addMoreBushes();

    if (exitPortal != null) {
      exitPortal!.position.x -= worldScrollSpeed * 0.45 * dt;

      if (exitPortal!.position.x < -200) {
        exitPortal!.position.x = size.x + 500;
        exitPortal!.position.y = 100 + math.Random().nextDouble() * (size.y - 200);
      }

      if (player != null) {
        final distance = player!.position.distanceTo(exitPortal!.position);
        final bool isCurrentlyTouching = distance < 120;

        if (isCurrentlyTouching) {
          if (!_isTouchingPortal) {
            _isTouchingPortal = true;
            _hasTriggeredMathThisTouch = false;
          }

          if (currentLevel % 3 == 0 && currentLevel < maxLevel) {
            if (!_hasTriggeredMathThisTouch) {
              startMathChallenge();
              _hasTriggeredMathThisTouch = true;
            }
          } else {
            currentLevel++;
            final extraSpeed = (currentLevel >= 4) ? 18.0 + (currentLevel - 3) * 8.0 : 0.0;
            worldScrollSpeed += extraSpeed;
            levelText.text = 'Màn $currentLevel / $maxLevel';
            shouldAddMoreBushes = true;
          }
        } else {
          _isTouchingPortal = false;
          _hasTriggeredMathThisTouch = false;
        }
      }
    }

    if (shouldAddMoreBushes) addMoreBushes();

    player?.applyPhysics(dt);
  }

  void addMoreBushes() {
    final random = math.Random();
    double lastX = bushes.isEmpty ? size.x : bushes.map((b) => b.position.x).reduce(math.max);

    final List<Component> toAdd = [];

    for (int i = 0; i < 4 + currentLevel ~/ 2; i++) {
      double x = lastX + 200 + random.nextDouble() * 150;
      double gapY = 100 + random.nextDouble() * (size.y - 200);

      final bush1 = Bush(Vector2(x, gapY - 100 - random.nextDouble() * 50));
      final bush2 = Bush(Vector2(x, gapY + 100 + random.nextDouble() * 50));

      bushes.add(bush1);
      bushes.add(bush2);
      toAdd.addAll([bush1, bush2]);

      lastX = x;
    }

    addAll(toAdd);
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (isGameOver || isMathChallengeActive) return;
    player?.jump();
  }

  void gameOver() {
    if (isGameOver) return;
    isGameOver = true;
    currentLevel = 1;
    levelText.text = 'Màn 1 / $maxLevel';
    pauseEngine();
    overlays.add('GameOver');
  }

  Future<void> restartGame() async {
    currentLevel = 1;
    overlays.removeAll(['GameOver', 'PauseMenu', 'MathChallenge']);
    _isTouchingPortal = false;
    _hasTriggeredMathThisTouch = false;
    _waitingForBushesAfterMath = false;
    _bushesPassedAfterMath = 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      overlays.add('StartScreen');
      pauseEngine();
    });

    await loadLevel(1);
  }

  void startMathChallenge() {
    if (isMathChallengeActive) return;

    isMathChallengeActive = true;
    pauseEngine();

    final rnd = math.Random();

    int minA, maxA, minB, maxB;

    if (currentLevel <= 3) {
      minA = 1;
      maxA = 6;
      minB = 0;
      maxB = 5;
    } else if (currentLevel <= 6) {
      minA = 5;
      maxA = 15;
      minB = 1;
      maxB = 12;
    } else {
      minA = 10;
      maxA = 30;
      minB = 5;
      maxB = 25;
    }

    int a = rnd.nextInt(maxA - minA + 1) + minA;
    int b = rnd.nextInt(maxB - minB + 1) + minB;

    final bool isPlus = (currentLevel <= 6) ? rnd.nextBool() : true;

    int correct;
    String question;

    if (isPlus || a < b) {
      correct = a + b;
      question = '$a + $b = ?';
    } else {
      correct = a - b;
      question = '$a - $b = ?';
    }

    if (currentLevel == 3 && correct > 5) {
      a = rnd.nextInt(5) + 1;
      b = rnd.nextInt(a);
      correct = a - b;
      question = '$a - $b = ?';
    }

    currentMathChallenge = MathChallenge(
      question: question,
      correctAnswer: correct,
      onCorrect: () {
        isMathChallengeActive = false;
        resumeEngine();
        overlays.remove('MathChallenge');
        _waitingForBushesAfterMath = true;
        _bushesPassedAfterMath = 0;
      },
      onWrong: () {
        gameOver();
      },
    );

    overlays.add('MathChallenge');
  }
}

// StartScreenOverlay (giữ nguyên)
class StartScreenOverlay extends StatefulWidget {
  final MazeGame game;

  const StartScreenOverlay({super.key, required this.game});

  @override
  State<StartScreenOverlay> createState() => _StartScreenOverlayState();
}

class _StartScreenOverlayState extends State<StartScreenOverlay> {
  final TextEditingController _nameController = TextEditingController();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.game.playerName;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withAlpha(225),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.indigo.shade900,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.cyanAccent, width: 3),
          ),
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Giải trí ngày tết',
                style: TextStyle(
                  fontSize: 48,
                  color: Colors.yellow,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(blurRadius: 10, color: Colors.black87)],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              const Text(
                'Nhập tên của bạn:',
                style: TextStyle(fontSize: 28, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameController,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 32, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Tên người chơi',
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.black38,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Colors.cyanAccent),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Colors.yellowAccent, width: 2.5),
                  ),
                ),
                autofocus: true,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 22),
                ),
              ],
              const SizedBox(height: 48),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 90, vertical: 22),
                  backgroundColor: Colors.green.shade700,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  final name = _nameController.text.trim();
                  if (name.isEmpty) {
                    setState(() => _errorMessage = 'Vui lòng nhập tên!');
                    return;
                  }

                  widget.game.playerName = name;
                  widget.game.overlays.remove('StartScreen');
                  widget.game.resumeEngine();
                  print('Tên đã cập nhật: $name');
                },
                child: const Text(
                  'CHƠI NGAY',
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Chúc bạn chơi vui vẻ!',
                style: TextStyle(fontSize: 22, color: Colors.orangeAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}

// Các class còn lại (Player, Bush, ExitPortal, HudButton, MathChallenge, MathChallengeOverlay, PauseMenuOverlay, GameOverOverlay) giữ nguyên như code cũ của bạn
// Copy phần còn lại từ code bạn gửi trước đó vào đây

class Player extends SpriteComponent with CollisionCallbacks {
  CircleHitbox? hitbox;
  double velocityY = 0.0;
  final double gravity = 1100.0;
  final double jumpForce = -380.0;

  Player({required Vector2 position})
      : super(position: position, size: Vector2(56, 56), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    try {
      sprite = await Sprite.load('pngtree-penguin-skiing-vector-png-image_12156156.png');
    } catch (e) {
      print('Không load được chim: $e');
      paint = Paint()..color = Colors.yellow;
    }
    hitbox = CircleHitbox(radius: 24);
    add(hitbox!);
  }

  void jump() {
    velocityY = jumpForce;
  }

  void applyPhysics(double dt) {
    velocityY += gravity * dt;
    position.y += velocityY * dt;

    final game = findGame() as MazeGame?;
    if (game != null) {
      position.y = position.y.clamp(30.0, game.size.y - 30.0);
      if (position.y <= 30.0 || position.y >= game.size.y - 30.0) {
        game.gameOver();
      }
    } else {
      position.y = position.y.clamp(30.0, 800.0);
    }
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    final game = findGame() as MazeGame?;
    if (other is Bush && game != null) {
      game.gameOver();
    }
  }
}

class Bush extends SpriteComponent with CollisionCallbacks {
  RectangleHitbox? hitbox;
  bool hasBeenPassedAfterMath = false;

  Bush(Vector2 pos)
      : super(position: pos, size: Vector2(88, 88), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    try {
      sprite = await Sprite.load('bush.png');
    } catch (e) {
      print('Không load được bụi: $e');
      paint = Paint()..color = Colors.green.shade700;
    }
    hitbox = RectangleHitbox(
      size: Vector2(76, 76),
      anchor: Anchor.center,
      position: size / 2,
    );
    add(hitbox!);
    hasBeenPassedAfterMath = false;
  }
}

class ExitPortal extends SpriteComponent {
  ExitPortal({required Vector2 position})
      : super(position: position, size: Vector2(120, 120), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    try {
      sprite = await Sprite.load('house.png');
    } catch (e) {
      print('Không load được nhà: $e');
      paint = Paint()..color = Colors.brown;
    }
    add(CircleHitbox(radius: 50));
  }
}

class HudButton extends PositionComponent with TapCallbacks {
  final VoidCallback onPressed;
  late TextComponent icon;

  HudButton({required Vector2 position, required this.onPressed})
      : super(position: position, size: Vector2(64, 64));

  @override
  Future<void> onLoad() async {
    icon = TextComponent(
      text: '⏸',
      textRenderer: TextPaint(
        style: const TextStyle(fontSize: 48, color: Colors.white70, fontWeight: FontWeight.bold),
      ),
      anchor: Anchor.center,
      position: size / 2,
    );
    add(icon);
  }

  @override
  void onTapDown(TapDownEvent event) {
    onPressed();
  }
}

class MathChallenge {
  final String question;
  final int correctAnswer;
  final VoidCallback onCorrect;
  final VoidCallback onWrong;

  MathChallenge({
    required this.question,
    required this.correctAnswer,
    required this.onCorrect,
    required this.onWrong,
  });
}

class MathChallengeOverlay extends StatefulWidget {
  final MazeGame game;

  const MathChallengeOverlay({super.key, required this.game});

  @override
  State<MathChallengeOverlay> createState() => _MathChallengeOverlayState();
}

class _MathChallengeOverlayState extends State<MathChallengeOverlay> {
  final TextEditingController _controller = TextEditingController();
  String errorMessage = '';

  @override
  Widget build(BuildContext context) {
    final challenge = widget.game.currentMathChallenge!;

    return Material(
      color: Colors.black.withAlpha(210),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              reverse: true,  // Quan trọng: scroll xuống dưới khi bàn phím mở
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 40,  // Padding bằng chiều cao bàn phím + dư chút
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(36),
                  constraints: BoxConstraints(maxWidth: 420, minWidth: 320),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade900,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.yellowAccent, width: 4),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'GIẢI PHÉP TÍNH',
                        style: TextStyle(fontSize: 52, color: Colors.yellow, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        challenge.question,
                        style: const TextStyle(fontSize: 80, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 40),
                      TextField(
                        controller: _controller,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 48, color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Nhập kết quả',
                          hintStyle: TextStyle(color: Colors.white60),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                        ),
                        autofocus: true,
                      ),
                      const SizedBox(height: 20),
                      if (errorMessage.isNotEmpty)
                        Text(errorMessage, style: const TextStyle(fontSize: 24, color: Colors.redAccent)),
                      const SizedBox(height: 30),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 20),
                          backgroundColor: Colors.green,
                        ),
                        onPressed: () {
                          final input = int.tryParse(_controller.text.trim());
                          if (input == challenge.correctAnswer) {
                            challenge.onCorrect();
                          } else {
                            setState(() {
                              errorMessage = 'Sai rồi! Kết quả đúng là ${challenge.correctAnswer}';
                            });
                            Future.delayed(const Duration(seconds: 2), () {
                              challenge.onWrong();
                            });
                          }
                        },
                        child: const Text('Kiểm tra', style: TextStyle(fontSize: 40)),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Nhập số và nhấn kiểm tra!',
                        style: TextStyle(fontSize: 24, color: Colors.orangeAccent),
                      ),
                      const SizedBox(height: 40),  // Padding dưới cùng để đẹp hơn
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class PauseMenuOverlay extends StatelessWidget {
  final MazeGame game;

  const PauseMenuOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withAlpha(160),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('TẠM DỪNG', style: TextStyle(fontSize: 64, color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 60),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 90, vertical: 28),
                backgroundColor: Colors.blue,
              ),
              onPressed: () {
                game.overlays.remove('PauseMenu');
                game.resumeEngine();
              },
              child: const Text('Tiếp tục', style: TextStyle(fontSize: 40)),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 90, vertical: 28),
                backgroundColor: Colors.orange,
              ),
              onPressed: () async {
                game.overlays.remove('PauseMenu');
                await game.restartGame();
              },
              child: const Text('Chơi lại', style: TextStyle(fontSize: 40)),
            ),
          ],
        ),
      ),
    );
  }
}

class GameOverOverlay extends StatelessWidget {
  final MazeGame game;

  const GameOverOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withAlpha(217),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('GAME OVER',
                style: TextStyle(fontSize: 72, color: Colors.redAccent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 28),
            const Text('Đụng bụi hoặc sai toán!',
                style: TextStyle(fontSize: 32, color: Colors.white70)),
            const SizedBox(height: 60),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 28),
                backgroundColor: Colors.orange,
              ),
              onPressed: () => game.restartGame(),
              child: const Text('Chơi lại', style: TextStyle(fontSize: 40)),
            ),
          ],
        ),
      ),
    );
  }
}