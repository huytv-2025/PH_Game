import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(
    GameWidget<MazeGame>(
      game: MazeGame(),
      overlayBuilderMap: {
        'GameOver': (context, game) => GameOverOverlay(game: game),
        'LevelComplete': (context, game) => LevelCompleteOverlay(game: game),
        'PauseMenu': (context, game) => PauseMenuOverlay(game: game),
        'MathChallenge': (context, game) => MathChallengeOverlay(game: game),
      },
    ),
  );
}

class MazeGame extends FlameGame with HasCollisionDetection, TapCallbacks {
  late Player player;
  late TextComponent levelText;
  late TextComponent timerText;
  HudButton? pauseButton;

  int currentLevel = 1;
  final int maxLevel = 10;
  bool isGameOver = false;
  bool isLevelComplete = false;
  double levelTimeLeft = 70.0;

  final List<Bush> bushes = [];
  ExitPortal? exitPortal;

  bool isMathChallengeActive = false;
  MathChallenge? currentMathChallenge;

  double worldScrollSpeed = 180.0;

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
    children
        .where((c) => c is Bush || c is Player || c is ExitPortal || c is HudButton)
        .forEach(remove);

    bushes.clear();
    exitPortal = null;
    pauseButton = null;

    pauseButton = HudButton(
      position: Vector2(size.x - 90, 90),
      onPressed: () {
        if (!isGameOver && !isLevelComplete && !isMathChallengeActive) {
          pauseEngine();
          overlays.add('PauseMenu');
        }
      },
    );
    add(pauseButton!);

    levelText = TextComponent(
      text: 'Màn $level / $maxLevel',
      position: Vector2(size.x / 2, 40),
      anchor: Anchor.center,
      textRenderer: TextPaint(
        style: const TextStyle(fontSize: 36, color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
    add(levelText);

    timerText = TextComponent(
      text: getLevelTime(level).toStringAsFixed(1),
      position: Vector2(size.x - 80, 40),
      anchor: Anchor.centerRight,
      textRenderer: TextPaint(
        style: const TextStyle(fontSize: 36, color: Colors.yellowAccent, fontWeight: FontWeight.bold),
      ),
    );
    add(timerText);

    generateObstacles(level);

    player = Player(position: Vector2(180, size.y / 2));
    await player.onLoad();
    add(player);

    exitPortal = ExitPortal(position: Vector2(size.x + 600, size.y / 2));
    await exitPortal!.onLoad();
    add(exitPortal!);

    isGameOver = false;
    isLevelComplete = false;
    isMathChallengeActive = false;
    levelTimeLeft = getLevelTime(level);

    worldScrollSpeed = 160.0 + level * 18.0;

    print('Level $level loaded - bushes: ${bushes.length}');
  }

  double getLevelTime(int level) => 75.0 - (level - 1) * 5.0;

  void generateObstacles(int level) {
    final random = math.Random();

    const double spacing = 320.0;
    double gapSize = 220.0 - (level * 8.0).clamp(0.0, 120.0);

    int columns = (size.x / spacing).ceil() + 5;

    for (int i = 0; i < columns; i++) {
      double x = size.x + i * spacing + random.nextDouble() * 100;
      double gapY = 100 + random.nextDouble() * (size.y - 200 - gapSize);

      bushes.add(Bush(Vector2(x, gapY - gapSize / 2 - 80)));
      bushes.add(Bush(Vector2(x, gapY + gapSize / 2 + 80)));
    }

    bushes.forEach(add);
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (isGameOver || isLevelComplete || isMathChallengeActive) return;

    levelTimeLeft -= dt;
    timerText.text = levelTimeLeft.toStringAsFixed(1);

    if (levelTimeLeft <= 0) {
      gameOver();
      return;
    }

    // Di chuyển bụi
    for (final bush in bushes) {
      bush.position.x -= worldScrollSpeed * dt;

      if (bush.position.x < -150) {
        bush.position.x = size.x + 150 + math.Random().nextDouble() * 200;
        bush.position.y = 60 + math.Random().nextDouble() * (size.y - 120);
      }
    }

    // Di chuyển cổng thoát
    if (exitPortal != null) {
      exitPortal!.position.x -= worldScrollSpeed * 0.45 * dt;

      if (exitPortal!.position.x < -200) {
        exitPortal!.position.x = size.x + 500;
        exitPortal!.position.y = 100 + math.Random().nextDouble() * (size.y - 200);
      }

      // Khi chim gần cổng thoát → kiểm tra toán (chủ động)
      if (player.position.distanceTo(exitPortal!.position) < 100) {
        if (currentLevel % 3 == 0 && currentLevel < maxLevel) {
          // Hiện toán khi gần cổng (màn 3,6,9...)
          startMathChallenge();
        } else {
          completeLevel();
        }
      }
    }

    player.applyPhysics(dt);
  }

  void onTapDown(TapDownEvent event) {
    if (isGameOver || isLevelComplete || isMathChallengeActive) return;
    player.jump();
  }

  void gameOver() {
    if (isGameOver) return;
    isGameOver = true;
    pauseEngine();
    overlays.add('GameOver');
  }

  void completeLevel() {
    if (isLevelComplete) return;
    isLevelComplete = true;
    pauseEngine();

    if (currentLevel >= maxLevel) {
      overlays.add('GameOver');
    } else {
      overlays.add('LevelComplete');
    }
  }

  Future<void> nextLevel() async {
    currentLevel++;
    overlays.remove('LevelComplete');
    await Future.delayed(const Duration(milliseconds: 400));
    await loadLevel(currentLevel);
    resumeEngine();
  }

  Future<void> restartGame() async {
    currentLevel = 1;
    overlays.removeAll(['GameOver', 'LevelComplete', 'PauseMenu', 'MathChallenge']);
    await Future.delayed(const Duration(milliseconds: 400));
    await loadLevel(1);
    resumeEngine();
  }

  void startMathChallenge() {
    if (isMathChallengeActive) return; // tránh hiện nhiều lần

    isMathChallengeActive = true;
    pauseEngine();

    final rnd = math.Random();
    final a = rnd.nextInt(20) + 5; // 5..24
    final b = rnd.nextInt(a + 1);  // 0..a để tránh âm
    final isPlus = rnd.nextBool();
    final correct = isPlus ? a + b : a - b;

    final options = [correct];
    while (options.length < 3) {
      final wrong = correct + rnd.nextInt(9) - 4; // sai lệch nhỏ
      if (!options.contains(wrong)) options.add(wrong);
    }
    options.shuffle();

    currentMathChallenge = MathChallenge(
      question: isPlus ? '$a + $b = ?' : '$a - $b = ?',
      options: options,
      correctIndex: options.indexOf(correct),
      onCorrect: () {
        isMathChallengeActive = false;
        resumeEngine();
        overlays.remove('MathChallenge');
        completeLevel(); // đúng → hoàn thành màn
      },
      onWrong: () {
        gameOver();
      },
    );

    overlays.add('MathChallenge');
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
      sprite = await Sprite.load('yellowbird-midflap.png');
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
      position.y = position.y.clamp(30.0, 800.0); // fallback
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
  final List<int> options;
  final int correctIndex;
  final VoidCallback onCorrect;
  final VoidCallback onWrong;

  MathChallenge({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.onCorrect,
    required this.onWrong,
  });
}

class MathChallengeOverlay extends StatelessWidget {
  final MazeGame game;

  const MathChallengeOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final challenge = game.currentMathChallenge!;

    return Material(
      color: Colors.black.withAlpha(210),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(36),
          decoration: BoxDecoration(
            color: Colors.indigo.shade900,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.yellowAccent, width: 4),
          ),
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'GIẢI NHANH!',
                style: TextStyle(fontSize: 52, color: Colors.yellow, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              Text(
                challenge.question,
                style: const TextStyle(fontSize: 80, color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 60),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
                        backgroundColor: Colors.deepPurple.shade600,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontSize: 52),
                      ),
                      onPressed: () {
                        if (i == challenge.correctIndex) {
                          challenge.onCorrect();
                        } else {
                          challenge.onWrong();
                        }
                      },
                      child: Text('${challenge.options[i]}'),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 28),
              const Text(
                'Chọn sai → thua ngay!',
                style: TextStyle(fontSize: 26, color: Colors.orangeAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Các overlay khác giữ nguyên (PauseMenu, LevelComplete, GameOver)
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
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 90, vertical: 28), backgroundColor: Colors.blue),
              onPressed: () {
                game.overlays.remove('PauseMenu');
                game.resumeEngine();
              },
              child: const Text('Tiếp tục', style: TextStyle(fontSize: 40)),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 90, vertical: 28), backgroundColor: Colors.orange),
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

class LevelCompleteOverlay extends StatelessWidget {
  final MazeGame game;

  const LevelCompleteOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withAlpha(166),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('HOÀN THÀNH!', style: TextStyle(fontSize: 68, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            Text('Màn ${game.currentLevel}', style: const TextStyle(fontSize: 48, color: Colors.white)),
            const SizedBox(height: 60),
            ElevatedButton(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 28), backgroundColor: Colors.green),
              onPressed: () => game.nextLevel(),
              child: const Text('Tiếp tục', style: TextStyle(fontSize: 40)),
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
    final isWin = game.currentLevel > game.maxLevel;

    return Material(
      color: Colors.black.withAlpha(217),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isWin ? 'CHIẾN THẮNG!' : 'GAME OVER',
              style: TextStyle(fontSize: 72, color: isWin ? Colors.yellow : Colors.redAccent, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 28),
            if (!isWin) const Text('Đụng bụi hoặc hết thời gian!', style: TextStyle(fontSize: 32, color: Colors.white70)),
            const SizedBox(height: 60),
            ElevatedButton(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 28), backgroundColor: Colors.orange),
              onPressed: () => game.restartGame(),
              child: const Text('Chơi lại', style: TextStyle(fontSize: 40)),
            ),
          ],
        ),
      ),
    );
  }
}