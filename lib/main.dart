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
          'StartScreen': (context, game) => StartScreenOverlay(game: game),
        },
      ),
    );
  }
}

class MazeGame extends FlameGame with HasCollisionDetection, TapCallbacks {
  Player? player;
  late TextComponent levelText;
  TextComponent? nameDisplay;
  HudButton? pauseButton;

  int currentLevel = 1;
  final int maxLevel = 10;
  bool isGameOver = false;

  static int highScore = 1; // Lưu màn cao nhất

  int? _lastReachedLevel; // Biến tạm lưu màn chơi lúc thua

  final List<Bush> bushes = [];
  final List<ExitPortal> portals = [];

  double worldScrollSpeed = 170.0;

  String playerName = 'Người chơi';

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
    print('Load level $level - Tên: $playerName');

    final toRemove = <Component>[];
    for (final c in children) {
      if (c is Bush || c is ExitPortal || c is Player ||
          (c is TextComponent && (c.text.contains('Người chơi:') || c.text.contains('Màn')))) {
        toRemove.add(c);
      }
    }
    for (final c in toRemove) remove(c);

    bushes.clear();
    portals.clear();
    nameDisplay = null;

    pauseButton = HudButton(
      position: Vector2(size.x - 90, 90),
      onPressed: () {
        if (!isGameOver) {
          pauseEngine();
          overlays.add('PauseMenu');
        }
      },
    );
    add(pauseButton!);

    levelText = TextComponent(
      text: 'Màn $level / $maxLevel',
      position: Vector2(size.x / 2, 100),
      anchor: Anchor.center,
      textRenderer: TextPaint(
        style: const TextStyle(fontSize: 36, color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
    add(levelText);

    nameDisplay = TextComponent(
      text: 'Người chơi: $playerName',
      position: Vector2(20, 40),
      anchor: Anchor.topLeft,
      textRenderer: TextPaint(
        style: const TextStyle(fontSize: 28, color: Colors.cyanAccent, fontWeight: FontWeight.w600),
      ),
    );
    add(nameDisplay!);

    generateObstacles(level);
    generatePortals(level);

    player = Player(position: Vector2(180, size.y / 2));
    await player!.onLoad();
    add(player!);

    isGameOver = false;

    worldScrollSpeed = 170.0 + (level - 1) * 14.0;
    if (level >= 7) worldScrollSpeed += (level - 6) * 6.0;

    print('Level $level - bushes: ${bushes.length} - portals: ${portals.length} - speed: $worldScrollSpeed');
  }

  void generateObstacles(int level) {
    final random = math.Random();
    final double spacing = 340.0 - level * 18.0;
    double gapSize = 240.0 - (level * 12.0).clamp(0.0, 140.0);
    int columns = (size.x / spacing).ceil() + 6 + level;

    for (int i = 0; i < columns; i++) {
      double x = size.x + i * spacing + random.nextDouble() * 120;
      double gapY = 120 + random.nextDouble() * (size.y - 240 - gapSize);

      bushes.add(Bush(Vector2(x, gapY - gapSize / 2 - 90)));
      bushes.add(Bush(Vector2(x, gapY + gapSize / 2 + 90)));

      if (level >= 4 && random.nextDouble() < 0.6) {
        bushes.add(Bush(Vector2(x + spacing / 2, gapY + random.nextDouble() * 120 - 60)));
      }
    }

    bushes.forEach(add);
  }

  void generatePortals(int level) {
    portals.clear();

    final random = math.Random();
    int portalCount = 2 + (level ~/ 2);

    double lastX = size.x + 500;

    for (int i = 0; i < portalCount; i++) {
      double x = lastX + 550 + random.nextDouble() * 350;
      double y = 80 + random.nextDouble() * (size.y - 160);

      final portal = ExitPortal(position: Vector2(x, y));
      portals.add(portal);
      add(portal);

      lastX = x;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (isGameOver) return;

    for (final bush in bushes) {
      bush.position.x -= worldScrollSpeed * dt;

      if (bush.position.x < -150) {
        bush.position.x = size.x + 200 + math.Random().nextDouble() * 300;
        bush.position.y = 60 + math.Random().nextDouble() * (size.y - 120);
      }
    }

    for (final portal in portals) {
      portal.position.x -= worldScrollSpeed * dt;

      if (portal.position.x < -200) {
        portal.position.x = size.x + 600 + math.Random().nextDouble() * 500;
        portal.position.y = 80 + math.Random().nextDouble() * (size.y - 160);
      }

      if (player != null) {
        final distance = player!.position.distanceTo(portal.position);
        if (distance < 100) {
          onReachPortal();
          portal.position.x += 800; // tránh trigger liên tục
        }
      }
    }

    player?.applyPhysics(dt);
  }

  void onReachPortal() {
    currentLevel++;
    if (currentLevel > maxLevel) currentLevel = maxLevel;

    if (currentLevel > highScore) {
      highScore = currentLevel;
    }

    levelText.text = 'Màn $currentLevel / $maxLevel';

    double speedBonus;
    if (currentLevel <= 4) {
      speedBonus = 14.0;
    } else if (currentLevel <= 7) {
      speedBonus = 11.0;
    } else {
      speedBonus = 7.0;
    }

    worldScrollSpeed += speedBonus;

    addMoreBushes();

    print('Đạt nhà → Level $currentLevel | Speed: $worldScrollSpeed | High: $highScore');
  }

  void addMoreBushes() {
    final random = math.Random();
    double lastX = bushes.isEmpty ? size.x : bushes.map((b) => b.position.x).reduce(math.max);

    final List<Component> toAdd = [];

    for (int i = 0; i < 3 + currentLevel ~/ 3; i++) {
      double x = lastX + 220 + random.nextDouble() * 180;
      double gapY = 100 + random.nextDouble() * (size.y - 200);

      final bush1 = Bush(Vector2(x, gapY - 110 - random.nextDouble() * 60));
      final bush2 = Bush(Vector2(x, gapY + 110 + random.nextDouble() * 60));

      bushes.add(bush1);
      bushes.add(bush2);
      toAdd.addAll([bush1, bush2]);

      lastX = x;
    }

    addAll(toAdd);
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (isGameOver) return;
    player?.jump();
  }

  void gameOver() {
    if (isGameOver) return;
    isGameOver = true;

    _lastReachedLevel = currentLevel; // Lưu màn chơi lúc thua

    pauseEngine();
    overlays.add('GameOver');
  }

  Future<void> restartGame() async {
    currentLevel = 1;
    worldScrollSpeed = 170.0;
    _lastReachedLevel = null; // Reset biến tạm
    overlays.removeAll(['GameOver', 'PauseMenu']);
    await loadLevel(currentLevel);
    resumeEngine();
  }
}

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
      print('Không load penguin: $e');
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

class Bush extends SpriteComponent {
  RectangleHitbox? hitbox;

  Bush(Vector2 pos)
      : super(position: pos, size: Vector2(88, 88), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    try {
      sprite = await Sprite.load('bush.png');
    } catch (e) {
      print('Không load bush: $e');
      paint = Paint()..color = Colors.green.shade700;
    }
    hitbox = RectangleHitbox(
      size: Vector2(76, 76),
      anchor: Anchor.center,
      position: size / 2,
    );
    add(hitbox!);
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
      print('Không load house: $e');
      paint = Paint()..color = Colors.brown;
    }
    add(CircleHitbox(radius: 55));
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
    final reached = game._lastReachedLevel ?? game.currentLevel;

    return Material(
      color: Colors.black.withAlpha(220),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.indigo.shade900,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.redAccent, width: 4),
          ),
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'GAME OVER',
                style: TextStyle(
                  fontSize: 60,
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Màn cao nhất: ${MazeGame.highScore}',
                style: const TextStyle(
                  fontSize: 32,
                  color: Colors.yellowAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Bạn đạt được màn $reached',
                style: const TextStyle(fontSize: 24, color: Colors.white70),
              ),
              const SizedBox(height: 40),
              const Text(
                'Bạn có muốn chơi tiếp không?',
                style: TextStyle(
                  fontSize: 32,
                  color: Colors.orangeAccent,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
                      backgroundColor: Colors.green.shade700,
                      minimumSize: const Size(140, 70),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      game.overlays.remove('GameOver');
                      game.restartGame();
                    },
                    child: const Text(
                      'CÓ',
                      style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
                      backgroundColor: Colors.red.shade700,
                      minimumSize: const Size(140, 70),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      game.overlays.remove('GameOver');
                      game.overlays.add('StartScreen');
                    },
                    child: const Text(
                      'KHÔNG',
                      style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}