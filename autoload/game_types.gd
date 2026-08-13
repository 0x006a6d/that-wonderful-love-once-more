extends Node

## グローバルな enum とゲーム全体で参照する型定義。
## 可変状態は持たない（可変状態は RunState のみ）。

enum Faction { PLAYER, ROBBER, CIVILIAN, POLICE }
enum CombatMode { UNARMED, PISTOL }
enum Act { PROLOGUE, INFILTRATION, ENGAGEMENT, BREACH, EPILOGUE }
enum Ending { IDEAL, NORMAL, DRIFT, FAILURE }
