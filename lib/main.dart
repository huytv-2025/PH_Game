import 'dart:math';

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
        'GameOver': (context, game) => GameOverOverlay(game: game as MazeGame),
        'LevelComplete': (context, game) => LevelCompleteOverlay(game: game as MazeGame),
        'PauseMenu': (context, game) => PauseMenuOverlay(game: game as MazeGame),
      },
    ),
  );
}

class MazeGame extends FlameGame with HasCollisionDetection {
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

  Vector2 moveDirection = Vector2.zero();

  bool _levelLoaded = false;

  @override
  Color backgroundColor() => const Color(0xFF0D1B2A);

  @override
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);

    if (!_levelLoaded && !gameSize.isZero()) {
      _levelLoaded = true;
      loadLevel(currentLevel);
    }
  }

  Future<void> loadLevel(int level) async {
    if (size.isZero()) {
      await Future.delayed(const Duration(milliseconds: 50));
      return loadLevel(level);
    }

    print('Loading level $level - canvas size: $size');

    // Xóa cũ
    children.where((c) => c is Bush || c is Player || c is ExitPortal || c is HudButton).forEach(remove);
    bushes.clear();
    exitPortal = null;
    pauseButton = null;

    // Pause button
    pauseButton = HudButton(
      position: Vector2(size.x - 90, 90),
      onPressed: () {
        if (!isGameOver && !isLevelComplete) {
          pauseEngine();
          overlays.add('PauseMenu');
        }
      },
    );
    add(pauseButton!);

    // Text
    levelText = TextComponent(
      text: 'Màn $level / $maxLevel',
      position: Vector2(size.x / 2, 40),
      anchor: Anchor.center,
      textRenderer: TextPaint(style: const TextStyle(fontSize: 36, color: Colors.white, fontWeight: FontWeight.bold)),
    );
    add(levelText);

    timerText = TextComponent(
      text: getLevelTime(level).toStringAsFixed(1),
      position: Vector2(size.x - 80, 40),
      anchor: Anchor.centerRight,
      textRenderer: TextPaint(style: const TextStyle(fontSize: 36, color: Colors.yellowAccent, fontWeight: FontWeight.bold)),
    );
    add(timerText);

    generateMaze(level);

    player = Player(position: Vector2(120, 120));
    await player.onLoad();
    add(player);

    await Future.delayed(Duration.zero);
    if (player.isCollidingWithAnyBush()) {
      print('Spawn collision detected - adjusting player position');
      player.position = Vector2(180, 180);
      if (player.isCollidingWithAnyBush()) {
        player.position = Vector2(240, 240);
      }
    }

    exitPortal = ExitPortal(position: getExitPosition(level));
    await exitPortal!.onLoad();
    add(exitPortal!);

    isGameOver = false;
    isLevelComplete = false;
    levelTimeLeft = getLevelTime(level);
    moveDirection = Vector2.zero();

    print('Level $level loaded - player: ${player.position}, exit: ${exitPortal?.position}');
  }

  double getLevelTime(int level) => 70.0 - (level - 1) * 5.0;

  double getPlayerSpeed(int level) => 180.0 + (level - 1) * 20.0;

  void generateMaze(int level) {
    const double cellSize = 64.0;
    final random = Random();

    bushes.clear();

    // Tường viền (luôn có)
    for (double x = 0; x < size.x; x += cellSize) {
      bushes.add(Bush(Vector2(x, 0)));
      bushes.add(Bush(Vector2(x, size.y - cellSize)));
    }
    for (double y = 0; y < size.y; y += cellSize) {
      bushes.add(Bush(Vector2(0, y)));
      bushes.add(Bush(Vector2(size.x - cellSize, y)));
    }

    // Bụi cố định - thiết kế để có đường đi
    List<List<double>> fixed = [];
    switch (level) {
      case 1:
        fixed = [
          [3, 3], [3, 4], [3, 5],
          [6, 3], [6, 4], [6, 5],
          [9, 3], [9, 4], [9, 5],
        ];
        break;
      case 2:
        fixed = [
          [2, 2], [2, 3], [2, 4],
          [5, 5], [5, 6], [5, 7],
          [8, 2], [8, 3], [8, 4],
          [11, 6], [11, 7], [11, 8],
        ];
        break;
      case 3:
        fixed = [
          [4, 1], [4, 2], [4, 3], [4, 4],
          [8, 5], [8, 6], [8, 7], [8, 8],
          [12, 2], [12, 3], [12, 4],
        ];
        break;
      case 4:
        fixed = [
          [3, 2], [3, 3], [3, 4],
          [7, 5], [7, 6], [7, 7],
          [10, 3], [10, 4], [10, 5],
        ];
        break;
      default:
        // Level cao hơn: ít bụi cố định hơn để dễ đi
        fixed = [];
    }

    for (var p in fixed) {
      bushes.add(Bush(Vector2(p[0] * cellSize, p[1] * cellSize)));
    }

    // Bụi ngẫu nhiên - GIẢM SỐ LƯỢNG để tránh chặn lối
    final int extraCount = 4 + (level - 1) * 1; // chỉ 4~13 bụi tùy level
    final Set<String> occupied = bushes.map((b) {
      int cx = (b.position.x / cellSize).floor();
      int cy = (b.position.y / cellSize).floor();
      return '$cx,$cy';
    }).toSet();

    int added = 0;
    while (added < extraCount) {
      int cx = 1 + random.nextInt((size.x / cellSize - 2).floor());
      int cy = 1 + random.nextInt((size.y / cellSize - 2).floor());
      String key = '$cx,$cy';
      if (!occupied.contains(key)) {
        bushes.add(Bush(Vector2(cx * cellSize, cy * cellSize)));
        occupied.add(key);
        added++;
      }
    }

    bushes.forEach(add);
    print('Level $level: ${bushes.length} bushes (fixed + $added random)');
  }

  Vector2 getExitPosition(int level) => Vector2(size.x - 120, size.y - 120);

  @override
  void update(double dt) {
    super.update(dt);

    if (isGameOver || isLevelComplete) return;

    levelTimeLeft -= dt;
    timerText.text = levelTimeLeft.toStringAsFixed(1);

    if (levelTimeLeft <= 0) {
      gameOver();
      return;
    }

    if (!moveDirection.isZero()) {
      player.move(moveDirection.normalized() * getPlayerSpeed(currentLevel) * dt);
    }

    if (exitPortal != null && player.position.distanceTo(exitPortal!.position) < 55) {
      completeLevel();
    }
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
    _levelLoaded = false;
    loadLevel(currentLevel);
    resumeEngine();
  }

  Future<void> restartGame() async {
    currentLevel = 1;
    overlays.remove('GameOver');
    overlays.remove('LevelComplete');
    overlays.remove('PauseMenu');
    await Future.delayed(const Duration(milliseconds: 400));
    _levelLoaded = false;
    loadLevel(1);
    resumeEngine();
  }
}

class Player extends SpriteComponent with CollisionCallbacks, DragCallbacks, HasGameReference<MazeGame> {
  CircleHitbox? hitbox;

  Player({required Vector2 position}) : super(position: position, size: Vector2(52, 52), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    try {
      sprite = await Sprite.load('yellowbird-midflap.png');
    } catch (e) {
      print('Load yellowbird failed: $e');
      paint = Paint()..color = Colors.yellow;
    }
    hitbox = CircleHitbox(radius: 22);
    add(hitbox!);
  }

  void move(Vector2 delta) {
    position.add(delta);
    position.x = position.x.clamp(26, game.size.x - 26);
    position.y = position.y.clamp(26, game.size.y - 26);
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is Bush) {
      game.gameOver();
      print('Collision with bush at ${other.position} - player at ${position}');
    }
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    if (game.isGameOver || game.isLevelComplete) return;
    final delta = event.localDelta;
    if (delta.length > 5) game.moveDirection = delta.normalized();
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    game.moveDirection = Vector2.zero();
  }
}

class Bush extends SpriteComponent with CollisionCallbacks {
  RectangleHitbox? hitbox;

  Bush(Vector2 pos) : super(position: pos, size: Vector2(64, 64), anchor: Anchor.topLeft);

  @override
  Future<void> onLoad() async {
    try {
      sprite = await Sprite.load('bush.png');
    } catch (e) {
      print('Load bush failed: $e');
      paint = Paint()..color = Colors.green;
    }
    hitbox = RectangleHitbox(size: Vector2(56, 56), anchor: Anchor.center, position: Vector2(32, 32));
    add(hitbox!);
  }
}

class ExitPortal extends SpriteComponent with CollisionCallbacks, HasGameReference<MazeGame> {
  ExitPortal({required Vector2 position}) : super(position: position, size: Vector2(90, 90), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    try {
      sprite = await Sprite.load('house.png');
    } catch (e) {
      print('Load house failed: $e');
      paint = Paint()..color = Colors.brown;
    }
    add(CircleHitbox(radius: 40));
  }
}

class HudButton extends PositionComponent with TapCallbacks {
  final VoidCallback onPressed;
  late TextComponent icon;

  HudButton({required Vector2 position, required this.onPressed}) : super(position: position, size: Vector2(64, 64));

  @override
  Future<void> onLoad() async {
    icon = TextComponent(
      text: '⏸',
      textRenderer: TextPaint(style: const TextStyle(fontSize: 48, color: Colors.white70, fontWeight: FontWeight.bold)),
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

// Overlays (giữ nguyên)
class PauseMenuOverlay extends StatelessWidget {
  final MazeGame game;
  const PauseMenuOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withAlpha(160),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('TẠM DỪNG', style: TextStyle(fontSize: 60, color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 50),
          ElevatedButton(
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 70, vertical: 20), backgroundColor: Colors.blue, foregroundColor: Colors.white),
            onPressed: () {
              game.overlays.remove('PauseMenu');
              game.resumeEngine();
            },
            child: const Text('Tiếp tục', style: TextStyle(fontSize: 32)),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 70, vertical: 20), backgroundColor: Colors.orange, foregroundColor: Colors.white),
            onPressed: () async {
              game.overlays.remove('PauseMenu');
              await game.restartGame();
            },
            child: const Text('Chơi lại', style: TextStyle(fontSize: 32)),
          ),
        ]),
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('HOÀN THÀNH!', style: TextStyle(fontSize: 64, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Text('Màn ${game.currentLevel}', style: const TextStyle(fontSize: 42, color: Colors.white)),
          const SizedBox(height: 50),
          ElevatedButton(
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 20), backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () => game.nextLevel(),
            child: const Text('Tiếp tục', style: TextStyle(fontSize: 32)),
          ),
        ]),
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(isWin ? 'CHIẾN THẮNG!' : 'GAME OVER', style: TextStyle(fontSize: 64, color: isWin ? Colors.yellow : Colors.redAccent, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          if (!isWin) const Text('Bạn đã chạm bụi cỏ hoặc hết thời gian!', style: TextStyle(fontSize: 28, color: Colors.white70)),
          const SizedBox(height: 40),
          ElevatedButton(
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 20), backgroundColor: Colors.orange, foregroundColor: Colors.white),
            onPressed: () => game.restartGame(),
            child: const Text('Chơi lại', style: TextStyle(fontSize: 32)),
          ),
        ]),
      ),
    );
  }
}

// Extension
extension on Player {
  bool isCollidingWithAnyBush() {
    final playerRect = hitbox?.toAbsoluteRect() ?? Rect.zero;
    for (final bush in game.bushes) {
      final bushRect = bush.hitbox?.toAbsoluteRect() ?? Rect.zero;
      if (playerRect.overlaps(bushRect)) return true;
    }
    return false;
  }
}